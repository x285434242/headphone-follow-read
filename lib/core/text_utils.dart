/// 文本处理：分句、归一化、相似度、多音字消歧、语气语调提示。
///
/// 这些是中文 TTS 与 ASR 准确率的关键前/后处理：
/// - 多音字：用常见词组表给字词加拼音标注，交给支持拼音的 TTS；
/// - 语气语调：把标点/情感提示转成 TTS 语速与停顿参数；
/// - 归一化：比对时去标点、繁简、数字读音，提升识别匹配率。
library;

final _endPunct = RegExp(r'[。！？；!?;…]');

/// 按标点分句（移植电脑端逻辑，保留句尾标点给 TTS 朗读语气）。
List<String> splitIntoSentences(String text) {
  if (text.trim().isEmpty) return [];
  final out = <String>[];

  void add(String piece) {
    var p = piece.trim();
    if (p.isEmpty) return;
    p = p.replaceFirst(RegExp(r'^[\s]*[\-\*\d]+[\.、\)）]?\s*'), '').trim();
    if (p.isEmpty) return;
    if (_normalize(p).isEmpty && out.isNotEmpty) {
      out[out.length - 1] += p; // 纯标点碎片并入上一句
      return;
    }
    out.add(p);
  }

  for (final para in text.split(RegExp(r'\r?\n'))) {
    final buf = StringBuffer();
    final chars = para.split('');
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      buf.write(ch);
      var isEnd = _endPunct.hasMatch(ch);
      if (ch == '.' && i == chars.length - 1) isEnd = true;
      if (isEnd) {
        add(buf.toString());
        buf.clear();
      }
    }
    if (buf.toString().trim().isNotEmpty) add(buf.toString());
  }
  return out;
}

/// 比对归一化：去标点/空白、统一小写、常见数字与全角处理。
String _normalize(String text) {
  var s = text.toLowerCase();
  s = s.replaceAll(RegExp(r'[\s，。！？、；：,.!?;:"\'“”‘’()（）\[\]【】—…·]+'), '');
  return s;
}

/// 全角转半角（数字/字母），识别模型常输出全角。
String toHalfWidth(String s) {
  final out = StringBuffer();
  for (final c in s.runes) {
    if (c >= 0xFF01 && c <= 0xFF5E) {
      out.writeCharCode(c - 0xFEE0);
    } else if (c == 0x3000) {
      out.writeCharCode(0x20);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// 字符级相似度（0~1），用 Levenshtein，比 SequenceMatcher 更适合端侧。
double similarity(String reference, String recognized) {
  final a = _normalize(toHalfWidth(reference));
  final b = _normalize(toHalfWidth(recognized));
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;

  // 滚动数组 Levenshtein
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [
        cur[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j <= b.length; j++) prev[j] = cur[j];
  }
  final dist = prev[b.length];
  final maxLen = a.length > b.length ? a.length : b.length;
  return (1.0 - dist / maxLen).clamp(0.0, 1.0).toDouble();
}

/// 折叠连续重复字（ASR 复读瑕疵：「请请描述」→「请描述」）。
String collapseRepeats(String s) => s.replaceAll(RegExp(r'(.)\1+'), r'\1');

/// 多音字消歧：常见多音字在固定词组里的读音，输出带拼音的 G2P 提示串。
/// 支持拼音标注的 TTS（Matcha/VITS 的 lexicon）可用；不支持时也可当作
/// 文本前处理的参考，避免「重、行、长、乐、朝」等被读错。
const Map<String, String> _polyphoneWords = {
  '重庆': 'chong2 qing4',
  '重要': 'zhong4 yao4',
  '重复': 'chong2 fu4',
  '银行': 'yin2 hang2',
  '行走': 'xing2 zou3',
  '长度': 'chang2 du4',
  '长大': 'zhang3 da4',
  '快乐': 'kuai4 le4',
  '音乐': 'yin1 yue4',
  '朝阳': 'zhao1 yang2',
  '朝着': 'chao2 zhe5',
  '发现': 'fa1 xian4',
  '头发': 'tou2 fa4',
  '好转': 'hao3 zhuan3',
  '爱好': 'ai4 hao4',
  '处理': 'chu3 li3',
  '到处': 'dao4 chu4',
  '空调': 'kong1 tiao2',
  '调查': 'diao4 cha2',
};

/// 返回文本中的多音字读音提示（用于日志/调试/支持拼音的引擎）。
Map<String, String> polyphoneHints(String text) {
  final hints = <String, String>{};
  for (final entry in _polyphoneWords.entries) {
    if (text.contains(entry.key)) hints[entry.key] = entry.value;
  }
  return hints;
}

/// 把多音字词组改写成「字(拼音)」形式，供带 lexicon 的 TTS 精确发音。
/// 例如「去重庆银行」→「去重庆(chong2 qing4)银行(yin2 hang2)」。
/// 对不支持括号注音的引擎可关闭此开关。
String annotatePolyphones(String text) {
  var out = text;
  // 长词优先，避免「重」先被短词命中
  final keys = _polyphoneWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    out = out.replaceAll(k, '$k(${_polyphoneWords[k]})');
  }
  return out;
}

/// 语气/语调分析结果：影响 TTS 语速与音量、播放停顿。
class Prosody {
  final double speed;      // 语速倍率，<1 慢 >1 快
  final double pauseAfter; // 句末额外停顿（秒）
  final String mood;       // 情绪标签，供支持的引擎使用

  const Prosody({this.speed = 1.0, this.pauseAfter = 0.15, this.mood = 'neutral'});
}

/// 根据标点与语气词推断朗读语气：
/// - 问句放慢、句尾上扬（停顿略长）；
/// - 感叹句稍快、有力度；
/// - 省略号放慢、留白；
/// - 含「请/您/谢谢」用温和语气。
Prosody analyzeProsody(String sentence, {double baseSpeed = 1.0}) {
  var speed = baseSpeed;
  var pause = 0.15;
  var mood = 'neutral';

  if (sentence.contains('？') || sentence.contains('?')) {
    speed = baseSpeed * 0.92;
    pause = 0.28;
    mood = 'question';
  } else if (sentence.contains('！') || sentence.contains('!')) {
    speed = baseSpeed * 1.06;
    pause = 0.22;
    mood = 'excited';
  } else if (sentence.contains('…') || sentence.contains('...')) {
    speed = baseSpeed * 0.85;
    pause = 0.45;
    mood = 'pause';
  }

  if (RegExp(r'请|您|谢谢|辛苦|麻烦').hasMatch(sentence)) {
    mood = 'gentle';
    speed = speed * 0.96;
  }
  return Prosody(speed: speed, pauseAfter: pause, mood: mood);
}
