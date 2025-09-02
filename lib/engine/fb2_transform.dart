// lib/engine/fb2_transform.dart

import 'dart:convert' show base64;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:xml/xml.dart';

import 'package:beam_reader/engine/elements/data_blocks/block_text.dart';
import 'package:beam_reader/engine/elements/data_blocks/inline_text.dart';
import 'package:beam_reader/engine/elements/data_blocks/text_run.dart';

/// =======================
///  Бинарники изображений
/// =======================

/// Собираем карту id -> bytes из <binary id="...">...</binary>
Map<String, Uint8List> extractBinaryMap(XmlDocument doc) {
  final map = <String, Uint8List>{};
  for (final bin in doc.findAllElements('binary')) {
    final id = bin.getAttribute('id');
    if (id == null) continue;
    final base64txt = bin.innerText.trim();
    if (base64txt.isEmpty) continue;
    try {
      map[id] = base64.decode(base64txt);
    } catch (_) {
      // игнорируем битые бинарники
    }
  }
  return map;
}

/// Декодируем bytes -> ui.Image
Future<ui.Image> decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// =======================
///     Типы блоков FB2
/// =======================

enum Fb2BlockTag {
  body,
  section,
  title,
  subtitle,
  p,
  emptyLine, // <empty-line/>
  poem,
  stanza,
  v,
  epigraph,
  annotation,
  cite,
  textAuthor,
  image,
  table,
  tr,
  td,
  unknown,
}

Fb2BlockTag fb2BlockTagFromName(String name) {
  switch (name) {
    case 'body': return Fb2BlockTag.body;
    case 'section': return Fb2BlockTag.section;
    case 'title': return Fb2BlockTag.title;
    case 'subtitle': return Fb2BlockTag.subtitle;
    case 'p': return Fb2BlockTag.p;
    case 'empty-line': return Fb2BlockTag.emptyLine;
    case 'poem': return Fb2BlockTag.poem;
    case 'stanza': return Fb2BlockTag.stanza;
    case 'v': return Fb2BlockTag.v;
    case 'epigraph': return Fb2BlockTag.epigraph;
    case 'annotation': return Fb2BlockTag.annotation;
    case 'cite': return Fb2BlockTag.cite;
    case 'text-author': return Fb2BlockTag.textAuthor;
    case 'image': return Fb2BlockTag.image;
    case 'table': return Fb2BlockTag.table;
    case 'tr': return Fb2BlockTag.tr;
    case 'td': return Fb2BlockTag.td;
    default: return Fb2BlockTag.unknown;
  }
}

bool _isStyleContainer(String name) =>
    name == 'title' ||
        name == 'subtitle' ||
        name == 'text-author' ||
        name == 'epigraph' ||
        name == 'cite';

/// =======================
///     Трансформер FB2
/// =======================

class Fb2Transformer {
  Fb2Transformer();
  int _sectionCounter = 0;
  static const Set<String> _blockTags = {
    'body','section','title','subtitle','p','empty-line','poem','stanza','v',
    'epigraph','annotation','cite','text-author','image','table','tr','td','th',
  };

  static const Set<String> _inlineTags = {
    'style','emphasis','strong','sub','sup','strikethrough','a','code','date',
  };

  // Листовые блоки = то, что рендерится строкой/абзацем
  static const Set<String> _leafBlocks = {
    'p','v','subtitle','text-author','empty-line','image','td','th',
  };

  // Что можно целиком пропустить (не лезем внутрь)
  static const Set<String> _skipEntirely = {
    'binary', // тяжелые данные картинок
  };

  int _idCounter = 0;
  String _nextId(String tag, List<String> path) {
    _idCounter++;
    return '${path.join("/")}:$tag#$_idCounter';
  }

  bool _isBlockTag(String name) => _blockTags.contains(name);
  bool _isInlineTag(String name) => _inlineTags.contains(name);

  // ---------- Публичные ----------
  List<BlockText> parseToBlocks(XmlNode root) {
    final out = <BlockText>[];
    _walk(root, out, path: const [], depth: 0, styleScope: null, currentSection: 0); // NEW
    return out;
  }
  List<List<InlineText>> groupIntoLines(List<BlockText> blocks) =>
      blocks.map((b) => b.inlines).toList(growable: false);

  // ---------- Рекурсия ----------
  void _walk(
      XmlNode node,
      List<BlockText> sink, {
        required List<String> path,
        required int depth,
        String? styleScope,
        required int currentSection, // NEW
      }) {
    if (node is XmlElement) {
      final tag = node.name.local;
      if (_skipEntirely.contains(tag)) return;

      final nextStyleScope = _isStyleContainer(tag) ? tag : styleScope;

      // если вошли в новую <section> — присваиваем уникальный id
      final nextSection = (tag == 'section') ? (++_sectionCounter) : currentSection; // NEW

      final isLeafBlock = _leafBlocks.contains(tag);
      final isTitleLeaf = tag == 'title' && !_hasChildTag(node, 'p');

      if (isLeafBlock || isTitleLeaf) {
        sink.add(_buildLeafBlock(
          node,
          path: [...path, tag],
          depth: depth,
          overrideTag: styleScope,
          sectionId: nextSection, // NEW
        ));
        return;
      }

      final nextDepth = (tag == 'section' || tag == 'poem' || tag == 'stanza' || tag == 'epigraph' || tag == 'cite')
          ? depth + 1
          : depth;

      for (final child in node.children) {
        _walk(child, sink,
          path: [...path, tag],
          depth: nextDepth,
          styleScope: nextStyleScope,
          currentSection: nextSection, // NEW
        );
      }
    }
  }

  BlockText _buildLeafBlock(
      XmlElement el, {
        required List<String> path,
        required int depth,
        String? overrideTag,
        required int sectionId, // NEW
      }) {
    final rawTag = el.name.local;
    final tag = overrideTag ?? rawTag;

    if (rawTag == 'empty-line') {
      return BlockText(
        tag: 'empty-line',
        id: _nextId('empty-line', path),
        inlines: const [],
        path: path,
        depth: depth,
        attrs: {'__section': '$sectionId'}, // NEW
      );
    }
    if (rawTag == 'image') {
      final at = _attrsOf(el)..['__section'] = '$sectionId'; // NEW
      return BlockText(
        tag: 'image',
        id: _nextId('image', path),
        inlines: const [],
        path: path,
        depth: depth,
        attrs: at,
      );
    }

    final inlines = _parseInlineChildren(el, path: path);
    final at = _attrsOf(el)..['__section'] = '$sectionId'; // NEW
    return BlockText(
      tag: tag,
      id: _nextId(tag, path),
      inlines: _coalesceTextRuns(inlines),
      path: path,
      depth: depth,
      attrs: at,
    );
  }

  List<InlineText> _parseInlineChildren(XmlElement parent, {required List<String> path}) {
    final out = <InlineText>[];
    for (final child in parent.children) {
      if (child is XmlText) {
        final t = _normalizeSpaces(child.text);
        if (t.isNotEmpty) {
          out.add(TextRun(text: t, path: [...path, '#text']));
        }
        continue;
      }
      if (child is XmlElement) {
        final tag = child.name.local;
        if (_isInlineTag(tag)) {
          final kids = _parseInlineChildren(child, path: [...path, tag]);
          out.add(InlineSpan(
            tag: tag,
            children: _coalesceTextRuns(kids),
            path: [...path, tag],
            attrs: _attrsOf(child),
          ));
          continue;
        }
        if (_isBlockTag(tag)) {
          // Блок внутри параграфа — считаем ошибкой, мягко «вытаскиваем» его текст
          final t = _normalizeSpaces(child.text);
          if (t.isNotEmpty) {
            out.add(TextRun(text: t, path: [...path, tag, '#text']));
          }
          continue;
        }
        // Неизвестный inline? — заберём как plain-text
        final t = _normalizeSpaces(child.text);
        if (t.isNotEmpty) {
          out.add(TextRun(text: t, path: [...path, tag, '#text']));
        }
      }
    }
    return out;
  }

  // ---------- Утилиты ----------
  bool _hasChildTag(XmlElement el, String want) =>
      el.children.any((c) => c is XmlElement && c.name.local == want);

  Map<String, String> _attrsOf(XmlElement el) {
    final m = <String, String>{};
    for (final a in el.attributes) {
      m[a.name.local] = a.value;
    }
    return m;
  }

  String _normalizeSpaces(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  List<InlineText> _coalesceTextRuns(List<InlineText> nodes) {
    if (nodes.isEmpty) return nodes;
    final out = <InlineText>[];

    bool isWordish(String ch) => RegExp(r'[A-Za-zА-Яа-яЁё0-9]').hasMatch(ch);

    void pushText(TextRun n) {
      if (out.isNotEmpty && out.last is TextRun) {
        final prev = out.removeLast() as TextRun;
        final a = prev.text;
        final b = n.text;
        if (a.isEmpty) {
          out.add(TextRun(text: b, path: prev.path));
          return;
        }
        final needSpace = isWordish(a[a.length - 1]) && b.isNotEmpty && isWordish(b[0]);
        out.add(TextRun(text: needSpace ? '$a $b' : a + b, path: prev.path));
      } else {
        out.add(n);
      }
    }

    for (final n in nodes) {
      if (n is TextRun) {
        if (n.text.isNotEmpty) pushText(n);
      } else if (n is InlineSpan) {
        final kids = _coalesceTextRuns(n.children);
        out.add(InlineSpan(tag: n.tag, children: kids, path: n.path, attrs: n.attrs));
      } else {
        out.add(n);
      }
    }
    return out;
  }
}
