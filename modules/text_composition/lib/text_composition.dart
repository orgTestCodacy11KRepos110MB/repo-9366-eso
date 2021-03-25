library text_composition;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'text_composition_config.dart';
import 'text_composition_effect.dart';

export 'text_composition_config.dart';
export 'text_composition_effect.dart';
export 'text_composition_page.dart';
export 'text_composition_widget.dart';

const indentation = "　";

T cast<T>(x, T defaultValue) => x is T ? x : defaultValue; // 安全转换

class TextPage {
  double percent;
  int number;
  int total;
  int chIndex;
  String info;
  final double height;
  final List<TextLine> lines;

  TextPage({
    this.percent = 0.0,
    this.total = 1,
    this.chIndex = 0,
    this.info = '',
    required this.number,
    required this.height,
    required this.lines,
  });
}

class TextLine {
  final String text;
  double dx;
  double _dy;
  double get dy => _dy;
  final double? letterSpacing;
  final bool isTitle;
  TextLine(
    this.text,
    this.dx,
    double dy, [
    this.letterSpacing = 0,
    this.isTitle = false,
  ]) : _dy = dy;

  justifyDy(double offsetDy) {
    _dy += offsetDy;
  }
}

void paintText(
    ui.Canvas canvas, ui.Size size, TextPage page, TextCompositionConfig config) {
  print("paintText ${page.chIndex} ${page.number} / ${page.total}");
  final lineCount = page.lines.length;
  final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
  final titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: config.fontSize,
    fontFamily: config.fontFamily,
    color: config.fontColor,
    height: config.fontHeight,
  );
  final style = TextStyle(
    fontSize: config.fontSize,
    fontFamily: config.fontFamily,
    color: config.fontColor,
    height: config.fontHeight,
  );
  for (var i = 0; i < lineCount; i++) {
    final line = page.lines[i];
    if (line.letterSpacing != null &&
        (line.letterSpacing! < -0.1 || line.letterSpacing! > 0.1)) {
      tp.text = TextSpan(
        text: line.text,
        style: line.isTitle
            ? TextStyle(
                letterSpacing: line.letterSpacing,
                fontWeight: FontWeight.bold,
                fontSize: config.fontSize,
                fontFamily: config.fontFamily,
                color: config.fontColor,
                height: config.fontHeight,
              )
            : TextStyle(
                letterSpacing: line.letterSpacing,
                fontSize: config.fontSize,
                fontFamily: config.fontFamily,
                color: config.fontColor,
                height: config.fontHeight,
              ),
      );
    } else {
      tp.text = TextSpan(text: line.text, style: line.isTitle ? titleStyle : style);
    }
    final offset = Offset(line.dx, line.dy);
    tp.layout();
    tp.paint(canvas, offset);
  }

  final styleInfo = TextStyle(
    fontSize: 12,
    fontFamily: config.fontFamily,
    color: config.fontColor,
  );
  tp.text = TextSpan(text: page.info, style: styleInfo);
  tp.layout(maxWidth: size.width - config.leftPadding - config.rightPadding - 60);
  tp.paint(canvas, Offset(config.leftPadding, size.height - 24));

  tp.text = TextSpan(
    text: '${page.number}/${page.total} ${(100 * page.percent).toStringAsFixed(2)}%',
    style: styleInfo,
  );
  tp.layout();
  tp.paint(canvas, Offset(size.width - config.rightPadding - tp.width, size.height - 24));
}

/// 样式设置与刷新
/// 动画设置与刷新
class TextComposition extends ChangeNotifier {
  final TextCompositionConfig config;
  final Duration duration;
  final FutureOr<List<String>> Function(int chapterIndex) loadChapter;
  final FutureOr Function(TextCompositionConfig config, double percent)? onSave;
  final FutureOr Function()? onToggleMenu;
  final Widget Function()? buildMenu;
  final String? name;
  final List<String> chapters;
  final List<AnimationController> _controllers;

  double _initPercent;
  int _firstChapterIndex;
  int _lastChapterIndex;

  int _firstIndex, _currentIndex, _lastIndex;
  int get firstIndex => _firstIndex;
  int get currentIndex => _currentIndex;
  int get lastIndex => _lastIndex;
  bool get _isFirstPage => _currentIndex <= _firstIndex;
  bool get _isLastPage => _currentIndex >= _lastIndex;

  final Map<int, TextPage> textPages;

  final int cutoffNext;
  final int cutoffPrevious;

  int _tapWithoutNoCounter;
  bool _disposed;
  bool? isForward;
  static const BASE = 4;
  static const QUARTER = BASE * 4;
  static const HALF = QUARTER * 2;
  static const TOTAL = HALF * 2;
  TextComposition({
    required this.config,
    required this.loadChapter,
    required this.chapters,
    this.name,
    this.onSave,
    this.onToggleMenu,
    this.buildMenu,
    percent = 0.0,
    this.cutoffPrevious = 8,
    this.cutoffNext = 92,
  })  : this._initPercent = percent,
        textPages = {},
        _controllers = [],
        // _pages = <Widget>[],
        _firstChapterIndex = (percent * chapters.length).floor(),
        _lastChapterIndex = (percent * chapters.length).floor(),
        _firstIndex = -1,
        _currentIndex = -1,
        _lastIndex = -1,
        duration = Duration(milliseconds: config.animationDuration),
        _tapWithoutNoCounter = 0,
        _disposed = false;
  //  {
  // _pages = [
  //   Container(
  //     color: const Color(0xFFFFFFCC),
  //     width: double.infinity,
  //     height: double.infinity,
  //     child: Column(
  //       mainAxisSize: MainAxisSize.min,
  //       mainAxisAlignment: MainAxisAlignment.center,
  //       children: [
  //         Text(name ?? ""),
  //         SizedBox(height: 10),
  //         Text("加载第${_lastChapterIndex + 1}个章节"),
  //         SizedBox(height: 10),
  //         Text("${chapters[_lastChapterIndex]}"),
  //         SizedBox(height: 30),
  //         CupertinoActivityIndicator(),
  //       ],
  //     ),
  //   )
  // ];
  // }

  Future<void> init(
      void Function(List<AnimationController> _controller) initControllers) async {
    initControllers(_controllers);
    if (_disposed) return;
    final pages = await startX(_firstChapterIndex);
    if (_disposed) return;
    _currentIndex = TOTAL * 12345 + HALF;
    final n =
        ((_initPercent * chapters.length - _firstChapterIndex) * pages.length).round();
    if (n < 2) {
      _firstIndex = _currentIndex;
    } else if (n < pages.length) {
      _firstIndex = _currentIndex - n + 1;
    }
    _lastIndex = _firstIndex + pages.length - 1;
    for (var i = 0; i < pages.length; i++) {
      this.textPages[_firstIndex + i] = pages[i];
    }
    final c = _currentIndex % TOTAL;
    for (var i = c - HALF, end = c; i < end; i++) {
      _controllers[i % TOTAL].value = 0;
    }
    for (var i = c, end = c + HALF; i < end; i++) {
      _controllers[i % TOTAL].value = 1;
    }
    _tapWithoutNoCounter = BASE;
    notifyListeners();
  }

  List<Widget> get pages {
    return [
      for (var i = _currentIndex + HALF, last = _currentIndex - HALF; i > last; i--)
        CustomPaint(
          painter: TextCompositionEffect(
            amount: _controllers[i % TOTAL],
            index: i,
            config: config,
            textComposition: this,
          ),
        ),
    ];
  }

  double getAnimationPostion(int index) => _controllers[index % TOTAL].value;

  _checkController(int index) {
    if (_disposed || _controllers.length != TOTAL) return;
    if (_tapWithoutNoCounter == HALF - BASE) {
      final c = index % TOTAL;
      for (var i = c - HALF, end = c - BASE; i < end; i++) {
        _controllers[i % TOTAL].value = 0;
      }
      for (var i = c + BASE, end = c + HALF; i < end; i++) {
        _controllers[i % TOTAL].value = 1;
      }
      _tapWithoutNoCounter = BASE;
      notifyListeners();
    } else {
      _tapWithoutNoCounter++;
    }
  }

  void _previousAnimation([bool showAnimation = true]) {
    if (showAnimation) {
      _controllers[(_currentIndex - 1) % TOTAL].forward();
    } else {
      _controllers[(_currentIndex - 1) % TOTAL].value = 1;
    }
  }

  void previousPage() {
    _checkController(_currentIndex);
    if (_disposed || _isFirstPage) return;
    if (_firstChapterIndex == textPages[_currentIndex]!.chIndex) previousChapter();
    if (_lastChapterIndex == textPages[_currentIndex]!.chIndex) nextChapter();
    _previousAnimation();
    _currentIndex--;
  }

  void _nextAnimation([bool showAnimation = true]) async {
    if (showAnimation) {
      await _controllers[_currentIndex % TOTAL].reverse();
    } else {
      _controllers[_currentIndex % TOTAL].value = 0;
    }
  }

  void nextPage() {
    _checkController(_currentIndex);
    if (_disposed || _isLastPage) return;
    if (_firstChapterIndex == textPages[_currentIndex]!.chIndex) previousChapter();
    if (_lastChapterIndex == textPages[_currentIndex]!.chIndex) nextChapter();
    _nextAnimation();
    _currentIndex++;
  }

  Future<void> goToPage(int index) async {
    // if (_disposed) return;
    // if (index > _currentIndex) {
    //   _controllers[index - 1].reverse();
    // } else {
    //   _controllers[index].forward();
    // }
    // _currentIndex = index;

    // notifyListeners();
    // for (var i = 0; i < _controllers.length; i++) {
    //   if (i < index - 1) {
    //     _controllers[i].value = 0;
    //   } else if (i > index) {
    //     _controllers[i].value = 1;
    //   }
    // }
  }

  void turnPage(DragUpdateDetails details, BoxConstraints dimens) {
    if (_disposed) return;
    final _ratio = details.delta.dx / dimens.maxWidth;
    if (isForward == null) {
      if (details.delta.dx > 0) {
        isForward = false;
      } else {
        isForward = true;
      }
    }
    if (isForward!) {
      _controllers[currentIndex % TOTAL].value += _ratio;
    } else if (!_isFirstPage) {
      _controllers[(currentIndex - 1) % TOTAL].value += _ratio;
    }
  }

  Future<void> onDragFinish() async {
    if (_disposed) return;
    if (isForward != null) {
      if (isForward!) {
        if (!_isLastPage &&
            _controllers[currentIndex % TOTAL].value <= (cutoffNext / 100 + 0.03)) {
          nextPage();
        } else {
          _controllers[currentIndex % TOTAL].forward();
        }
      } else {
        if (!_isFirstPage &&
            _controllers[(currentIndex - 1) % TOTAL].value >=
                (cutoffPrevious / 100 + 0.05)) {
          previousPage();
        } else {
          if (_isFirstPage) {
            _controllers[currentIndex % TOTAL].forward();
          } else {
            _controllers[(currentIndex - 1) % TOTAL].reverse();
          }
        }
      }
    }
    isForward = null;
  }

  @override
  void dispose() {
    _disposed = true;
    if (textPages[currentIndex] != null) {
      onSave?.call(config, textPages[currentIndex]!.percent);
    }
    _controllers.forEach((c) => c.dispose());
    _controllers.clear();
    textPages.forEach((key, value) => value.lines.clear());
    textPages.clear();
    super.dispose();
  }

  void updateConfig({
    bool? animationTap,
    bool? animationDrag,
    bool? animationDragEnd,
    bool? justifyHeight,
    bool? showInfo,
    String? animation,
    int? animationDuration,
    double? topPadding,
    double? leftPadding,
    double? bottomPadding,
    double? rightPadding,
    double? titlePadding,
    double? paragraphPadding,
    double? columnPadding,
    int? columns,
    int? indentation,
    Color? fontColor,
    double? fontSize,
    double? fontHeight,
    String? fontFamily,
    String? background,
  }) {
    if (config.updateConfig(
      animationTap: animationTap,
      animationDrag: animationDrag,
      animationDragEnd: animationDragEnd,
      justifyHeight: justifyHeight,
      showInfo: showInfo,
      animation: animation,
      animationDuration: animationDuration,
      topPadding: topPadding,
      leftPadding: leftPadding,
      bottomPadding: bottomPadding,
      rightPadding: rightPadding,
      titlePadding: titlePadding,
      paragraphPadding: paragraphPadding,
      columnPadding: columnPadding,
      columns: columns,
      indentation: indentation,
      fontColor: fontColor,
      fontSize: fontSize,
      fontHeight: fontHeight,
      fontFamily: fontFamily,
      background: background,
    )) notifyListeners();
  }

  var _previousChapterLoading = false;
  Future<void> previousChapter() async {
    if (_disposed || _firstChapterIndex <= 0 || _previousChapterLoading) return;
    _previousChapterLoading = true;
    final pages = await startX(_firstChapterIndex - 1);
    if (_disposed) return;
    for (var i = 0; i < pages.length; i++) {
      this.textPages[_firstIndex - pages.length + i] = pages[i];
    }
    _firstIndex -= pages.length;
    _firstChapterIndex--;
    _previousChapterLoading = false;
  }

  var _nextChapterLoading = false;
  Future<void> nextChapter([bool animation = true]) async {
    if (_disposed || _lastChapterIndex >= chapters.length - 1 || _nextChapterLoading)
      return;
    _nextChapterLoading = true;
    final pages = await startX(_lastChapterIndex + 1);
    if (_disposed) return;
    for (var i = 0; i < pages.length; i++) {
      this.textPages[_lastIndex + 1 + i] = pages[i];
    }
    _lastIndex += pages.length;
    _lastChapterIndex++;
    _nextChapterLoading = false;
  }

  Future<List<TextPage>> startX(int index) async {
    final pages = <TextPage>[];
    if (_disposed) return pages;
    final paragraphs = await loadChapter(index);
    if (_disposed) return pages;
    final size = ui.window.physicalSize / ui.window.devicePixelRatio;
    final columns = config.columns > 0
        ? config.columns
        : size.width > 1200
            ? 3
            : size.width > 580
                ? 2
                : 1;
    final _width = (size.width -
            config.leftPadding -
            config.rightPadding -
            (columns - 1) * config.columnPadding) /
        columns;
    final _width2 = _width - config.fontSize;
    final _height = size.height - (config.showInfo ? 24 : 0) - config.bottomPadding;
    final _height2 = _height - config.fontSize * config.fontHeight;

    final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    final offset = Offset(_width, 1);
    final _dx = config.leftPadding;
    final _dy = config.topPadding;

    var lines = <TextLine>[];
    var columnNum = 1;
    var dx = _dx;
    var dy = _dy;
    var startLine = 0;

    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: config.fontSize,
      fontFamily: config.fontFamily,
      color: config.fontColor,
    );
    final style = TextStyle(
      fontSize: config.fontSize,
      fontFamily: config.fontFamily,
      color: config.fontColor,
    );

    // String t = chapters[index].replaceAll(RegExp("^\s*|\n|\s\$"), "");
    final chapter = chapters[index].isEmpty ? "第$index章" : chapters[index];
    var _t = chapter;
    while (true) {
      tp.text = TextSpan(text: _t, style: titleStyle);
      tp.layout(maxWidth: _width);
      final textCount = tp.getPositionForOffset(offset).offset;
      final text = _t.substring(0, textCount);
      double? spacing;
      if (tp.width > _width2) {
        tp.text = TextSpan(text: text, style: titleStyle);
        tp.layout();
        double _spacing = (_width - tp.width) / textCount;
        if (_spacing < -0.1 || _spacing > 0.1) {
          spacing = _spacing;
        }
      }
      lines.add(TextLine(text, dx, dy, spacing, true));
      dy += tp.height;
      if (_t.length == textCount) {
        break;
      } else {
        _t = _t.substring(textCount);
      }
    }
    dy += config.titlePadding;

    var pageIndex = 1;

    /// 下一页 判断分页 依据: `_boxHeight` `_boxHeight2`是否可以容纳下一行
    void newPage([bool shouldJustifyHeight = true, bool lastPage = false]) {
      if (shouldJustifyHeight && config.justifyHeight) {
        final len = lines.length - startLine;
        double justify = (_height - dy) / (len - 1);
        for (var i = 0; i < len; i++) {
          lines[i + startLine].justifyDy(justify * i);
        }
      }
      if (columnNum == columns || lastPage) {
        pages.add(TextPage(
          lines: lines,
          height: dy,
          number: pageIndex++,
          info: chapter,
          chIndex: index,
        ));
        lines = <TextLine>[];
        columnNum = 1;
        dx = _dx;
      } else {
        columnNum++;
        dx += _width + config.columnPadding;
      }
      dy = _dy;
      startLine = lines.length;
    }

    for (var p in paragraphs) {
      p = indentation * config.indentation + p;
      while (true) {
        tp.text = TextSpan(text: p, style: style);
        tp.layout(maxWidth: _width);
        final textCount = tp.getPositionForOffset(offset).offset;
        double? spacing;
        final text = p.substring(0, textCount);
        if (tp.width > _width2) {
          tp.text = TextSpan(text: text, style: style);
          tp.layout();
          spacing = (_width - tp.width) / textCount;
        }
        lines.add(TextLine(text, dx, dy, spacing));
        dy += tp.height;
        if (p.length == textCount) {
          if (dy > _height2) {
            newPage();
          } else {
            dy += config.paragraphPadding;
          }
          break;
        } else {
          p = p.substring(textCount);
          if (dy > _height2) {
            newPage();
          }
        }
      }
    }
    if (lines.isNotEmpty) {
      newPage(false, true);
    }
    if (pages.length == 0) {
      pages.add(TextPage(
        lines: [],
        height: config.topPadding + config.bottomPadding,
        number: 1,
        info: chapter,
        chIndex: index,
      ));
    }

    final basePercent = index / chapters.length;
    final total = pages.length;
    pages.forEach((page) {
      page.total = total;
      page.percent = page.number / pages.length / chapters.length + basePercent;
    });
    if (name != null) {
      pages[0].info = name!;
    }
    return pages;
  }
}