import 'dart:io';
import 'dart:convert' show HtmlEscape, HtmlEscapeMode;
import 'package:logging/logging.dart';

final Logger _log = Logger('');
final repoBase = '..';

final warning = '''{%- comment %}
WARNING: Do NOT EDIT this file directly. It is autogenerated by
  ${Platform.script.path.replaceFirst(RegExp(r'^.*site-www/'), '')}
from sources in the example folder.
{% endcomment -%}
''';

final sources = [
  // Entry format: [ src_path, tip_data_path, target_HTML_file_path ]
  _SrcAndTipPaths(
    '$repoBase/examples/misc/lib/pi_monte_carlo.dart',
    '$repoBase/examples/misc/lib/pi_monte_carlo_tooltips.html',
    '$repoBase/src/_main-example.html',
  ),
  _SrcAndTipPaths(
    '$repoBase/examples/misc/bin/dcat.dart',
    '$repoBase/examples/misc/bin/dcat_tooltips.html',
    '$repoBase/src/_tutorials/server/_dcat-example.html',
  ),
];

void main() {
  Logger.root.level = Level.OFF;
  Logger.root.onRecord.listen((LogRecord rec) => print('>> ${rec.message}'));

  sources.forEach(_processSrc);
}

void _processSrc(_SrcAndTipPaths paths) {
  _log.info('Processing $paths');

  final srcAsHtmlWithTips =
      _SrcWithTips(paths.srcPath, paths.toolTipDataPath).srcHtmlWithTips();
  final html = [
    warning,
    '<pre class="prettyprint lang-dart">\n',
    '<code>\n',
    srcAsHtmlWithTips.join('\n'),
    '</code>\n'
        '</pre>\n',
  ].join('');
  File(paths.htmlPath).writeAsStringSync(html);
}

class _SrcWithTips {
  final HtmlEscape _htmlEscape = HtmlEscape(HtmlEscapeMode(escapeLtGt: true));
  final tipRegExp = RegExp(r'^(.*?) ?//!tip\("([^"]+)"\)$');
  final isNotBlankRegExp = RegExp(r'\S');
  List<List<String>> tooltips;

  /// Path to source code with tool tip markers
  final String srcPath;

  /// Source line number (starting at 1 not 0) as lines are being processed.
  int lineNum = 1;

  /// Path to file containing tool tip data
  final String toolTipDataPath;

  int indexOfNextTooltip = 0;

  _SrcWithTips(this.srcPath, this.toolTipDataPath)
      : tooltips = _tooltips(toolTipDataPath).toList();

  // Side-effect: updates lineNum
  List<String> srcHtmlWithTips() {
    final result = <String>[];
    final srcLines = srcLinesWithoutInitialCommentBlock();
    final tooltipAnchors = <String>[];

    for (int i = 0; i < srcLines.length; i++, lineNum++) {
      var line = srcLines[i];
      if (line.contains('//!web-only') ||
          line.contains('#docregion') ||
          line.contains('#enddocregion')) {
        _log.info('Src skip web-only: $lineNum: $line');
        continue;
      }
      var lineWithoutTipInstructions =
          extractTooltipAnchors(lineNum, line, tooltipAnchors);
      if (isNotBlankRegExp.hasMatch(lineWithoutTipInstructions)) {
        var lineWithMarkup = processTipInstruction(
            tooltipAnchors, lineNum, lineWithoutTipInstructions);
        result.add(lineWithMarkup);
        tooltipAnchors.clear();
        _log.info('Src added markup #$lineNum: $line ($lineWithMarkup)');
      } else if (tooltipAnchors.isEmpty) {
        // This is a blank line
        result.add(line);
        _log.info('Src blank line #$lineNum: $line');
      } else {
        // [line] only contains tooltip instructions. Don't add it to [result].
        // The accumulated [tooltipAnchors] apply to the next line. Fall
        // through.
        _log.info('Src extracted tips #$lineNum: $line');
      }
      // lineNum++;
    }
    return result;
  }

  /// Return a version of [line] with each [tooltipAnchors] replaced
  /// by a popover HTML anchor element.
  ///
  /// [tooltipAnchors] are (unescaped) tooltip anchor text strings.
  /// [line] is an unescaped source line without tooltip instructions.
  ///
  /// Side-effect: increments [indexOfNextTooltip] as it processes tips.
  String processTipInstruction(
      List<String> tooltipAnchors, int lineNum, String line /*src line*/) {
    _log.fine(line);
    line = htmlEscape(line);

    for (var anchorText in tooltipAnchors) {
      final escapedAnchorText = htmlEscape(anchorText);
      if (!line.contains(escapedAnchorText))
        throw "Error: $srcPath:$lineNum doesn't contain "
            "the tip anchor text '$anchorText': '$line'";
      final tooltip = tooltips[indexOfNextTooltip],
          tooltipAnchor = tooltip[0],
          tooltipTitle = tooltip[1],
          tooltipText = tooltip[2];
      indexOfNextTooltip++;
      if (tooltipAnchor != anchorText)
        throw "Error in tooltip data entry order: "
            "expected tip for '$anchorText', but instead found tip for '$tooltipAnchor'. Aborting.";
      _log.fine('  ** Replacing "$escapedAnchorText" with tooltip');
      final anchorWithTip =
          '<a tabindex="0" role="button" data-toggle="popover"' +
              (tooltipTitle.isEmpty ? '' : ' title="$tooltipTitle"') +
              ' data-content="$tooltipText">$escapedAnchorText</a>';
      line = line.replaceFirst(escapedAnchorText, anchorWithTip);
    }
    return line;
  }

  /// Extracts from [line] the anchor text from tooltips in that line, and adds
  /// the text to [tooltipAnchors] as (unescaped) text. Returns the portion of
  /// the line without the tip instructions
  String extractTooltipAnchors(
      int lineNum, String line, List<String> tooltipAnchors) {
    while (line.contains('//!tip(')) {
      var match = tipRegExp.firstMatch(line);
      if (match == null) return line;
      final lineWithoutTipInstruction = match[1];
      final tooltipAnchorText = match[2];
      if (tooltipAnchorText != null) {
        tooltipAnchors.add(tooltipAnchorText);
      }
      line = lineWithoutTipInstruction ?? '';
    }
    return line;
  }

  // Side-effect: updates lineNum
  List<String> srcLinesWithoutInitialCommentBlock() {
    final lines = File(srcPath).readAsLinesSync();
    while (!lines.first.startsWith('import')) {
      // Skip initial comment block
      _log.info('Src skip init comment: $lineNum: ${lines.first}');
      lineNum++;
      lines.removeAt(0);
    }
    return lines
        // pi_monte_carlo.dart specific adjustment
        .map((line) => line.replaceFirst('numIterations', '500'))
        .toList();
  }

  String htmlEscape(String s) => _htmlEscape.convert(s);
}

Iterable<List<String>> _tooltips(String toolTipDataPath) sync* {
  final _tooltipLineRE =
      RegExp(r'^\s*<li name="(.*?)"(\s+title="(.*?)")?>(.*?)(</li>)?$');
  final _tooltipLineEndRE = RegExp(r'^\s*(.*?)(</li>)?$');
  final lines = File(toolTipDataPath).readAsLinesSync().iterator;
  _log.info('Reading tool tips $toolTipDataPath:');

  while (lines.moveNext()) {
    final line = lines.current;
    final match = _tooltipLineRE.firstMatch(line);
    _log.info('  ${match == null ? "Skipping" : "Processing"}: $line.');
    if (match == null) continue;

    String name = match[1] ?? '';
    String optionalTitle = match[3] ?? '';
    String tooltip = match[4] ?? '';
    String? liClosingTag = match[5];
    _log.fine('  >> $name | $optionalTitle | $tooltip | $liClosingTag');

    while (liClosingTag == null && lines.moveNext()) {
      final line = lines.current;
      final match = _tooltipLineEndRE.firstMatch(line);
      if (match == null) {
        _log.info('Skipping data: $line');
      } else {
        _log.info('Processing data: $line');
        tooltip = _join(tooltip, match[1] ?? '');
        liClosingTag = match[2];
      }
    }

    if (liClosingTag == null)
      throw 'Could not find closing <li> tag for line starting at "$tooltip"';

    yield [name, optionalTitle, tooltip];
  }
}

/// Return the concatentation of s1 and s2, separated by a space if both are
/// nonempty.
String _join(String s1, String s2) => s1.isEmpty
    ? s2
    : s2.isEmpty
        ? s1
        : '$s1 $s2';

class _SrcAndTipPaths {
  final String srcPath;
  final String toolTipDataPath;

  /// Path to src as HTML marked up with tool tips
  final String htmlPath;

  _SrcAndTipPaths(this.srcPath, this.toolTipDataPath, this.htmlPath);

  @override
  String toString() =>
      'src: "$srcPath", tool tips: "$toolTipDataPath", HTML: "$htmlPath"';
}
