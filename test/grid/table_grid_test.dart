import 'package:curriculum/curriculum.dart';
import 'package:test/test.dart';

import '../support/html_builders.dart';

/// 建一个收集诊断的上下文。
ParseContext ctx() => ParseContext(options: const ParseOptions());

/// 统计某类诊断的条数。
int countOf(ParseContext c, ParseWarningKind kind) => c.counters[kind] ?? 0;

void main() {
  group('TableGrid 基础', () {
    test('无跨度的 3x3', () {
      final grid = TableGrid.from(buildPlainTable(3, 3));
      expect(grid.rowCount, 3);
      expect(grid.columnCount, 3);
      expect(grid.originCells.length, 9);
      expect(grid.rows.expand((r) => r).where((c) => c.isSpanned), isEmpty);
      expect(grid.cellAt(1, 2).element!.text, 'r1c2');
    });

    test('rowspan=2：第二行同列是 spanned', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A', rowSpan: 2), const CellSpec('B')],
          <CellSpec>[const CellSpec('C')],
        ]),
      );
      expect(grid.rowCount, 2);
      expect(grid.columnCount, 2);
      expect(grid.cellAt(0, 0).isOrigin, isTrue);
      expect(grid.cellAt(0, 0).rowSpan, 2);
      expect(grid.cellAt(1, 0).isSpanned, isTrue);
      expect(grid.cellAt(1, 0).origin, same(grid.cellAt(0, 0)));
      // rowspan 占掉了 (1,0)，所以 C 落在第 1 列。
      expect(grid.cellAt(1, 1).element!.text, 'C');
      expect(grid.originCells.length, 3);
    });

    test('colspan=2：同一行右侧是 spanned', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A', colSpan: 2), const CellSpec('B')],
          <CellSpec>[const CellSpec('C'), const CellSpec('D')],
        ]),
      );
      expect(grid.columnCount, 3);
      expect(grid.cellAt(0, 1).isSpanned, isTrue);
      expect(grid.cellAt(0, 1).origin, same(grid.cellAt(0, 0)));
      expect(grid.cellAt(0, 2).element!.text, 'B');
      expect(grid.cellAt(1, 0).element!.text, 'C');
    });

    test('rowspan=2 colspan=2：四个槽位指向同一个 origin 对象', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A', rowSpan: 2, colSpan: 2)],
          <CellSpec>[const CellSpec('B'), const CellSpec('C')],
        ]),
      );
      // A 占掉第 0、1 两列，所以第 1 行的 B、C 落到第 2、3 列，共 4 列。
      expect(grid.columnCount, 4);
      final origin = grid.cellAt(0, 0);
      expect(origin.isOrigin, isTrue);
      expect(grid.cellAt(0, 1).origin, same(origin));
      expect(grid.cellAt(1, 0).origin, same(origin));
      expect(grid.cellAt(1, 1).origin, same(origin));
      // 第 0 行只有 A 覆盖到的两列，其余是补齐出来的空洞。
      expect(grid.cellAt(0, 2).isAbsent, isTrue);
      expect(grid.cellAt(1, 2).element!.text, 'B');
      expect(grid.cellAt(1, 3).element!.text, 'C');
      expect(grid.originCells.length, 3);
    });

    test('跨行跳过：后续行从正确的列继续', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A'), const CellSpec('B'), const CellSpec('C')],
          <CellSpec>[const CellSpec('X', rowSpan: 2), const CellSpec('D'), const CellSpec('E')],
          <CellSpec>[const CellSpec('F'), const CellSpec('G')],
        ]),
      );
      // rowspan=2 在最后一行被钳制，覆盖第 1、2 行。
      expect(grid.cellAt(2, 0).isSpanned, isTrue);
      expect(grid.cellAt(2, 0).origin, same(grid.cellAt(1, 0)));
      expect(grid.cellAt(2, 1).element!.text, 'F');
      expect(grid.cellAt(2, 2).element!.text, 'G');
    });
  });

  group('TableGrid 结构边界', () {
    test('单元格内嵌套表格不产生外层行', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[
            const CellSpec('<table><tr><td>内1</td></tr><tr><td>内2</td></tr></table>'),
            const CellSpec('B'),
          ],
          <CellSpec>[const CellSpec('C'), const CellSpec('D')],
        ]),
      );
      expect(grid.rowCount, 2);
      expect(grid.columnCount, 2);
      expect(grid.cellAt(0, 0).rowSpan, 1);
    });

    test('参差行：短行尾部是 absent 而非 spanned', () {
      final c = ctx();
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[
            const CellSpec('a'),
            const CellSpec('b'),
            const CellSpec('c'),
            const CellSpec('d'),
            const CellSpec('e'),
          ],
          <CellSpec>[const CellSpec('f'), const CellSpec('g')],
        ]),
        context: c,
      );
      expect(grid.columnCount, 5);
      expect(grid.cellAt(1, 1).isOrigin, isTrue);
      expect(grid.cellAt(1, 2).isAbsent, isTrue);
      expect(grid.cellAt(1, 4).isAbsent, isTrue);
      expect(countOf(c, ParseWarningKind.raggedRow), 1);
    });

    test('rowspan="0" 延伸到表格末尾', () {
      final c = ctx();
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[
            const CellSpec('A', attributes: <String, String>{'rowspan': '0'}),
            const CellSpec('B'),
          ],
          <CellSpec>[const CellSpec('C')],
          <CellSpec>[const CellSpec('D')],
        ]),
        context: c,
      );
      expect(grid.cellAt(0, 0).rowSpan, 3);
      expect(grid.cellAt(2, 0).origin, same(grid.cellAt(0, 0)));
      expect(grid.cellAt(2, 1).element!.text, 'D');
      expect(countOf(c, ParseWarningKind.zeroRowspan), 1);
    });

    test('非法跨度被钳制为 1 并留下警告', () {
      final c = ctx();
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[
            const CellSpec('A', attributes: <String, String>{'rowspan': 'abc'}),
            const CellSpec('B', attributes: <String, String>{'colspan': '0'}),
            const CellSpec('C', attributes: <String, String>{'rowspan': '-1'}),
          ],
        ]),
        context: c,
      );
      expect(grid.cellAt(0, 0).rowSpan, 1);
      expect(grid.cellAt(0, 1).colSpan, 1);
      expect(grid.cellAt(0, 2).rowSpan, 1);
      expect(countOf(c, ParseWarningKind.invalidSpan), 3);
      expect(grid.originCells.length, 3);
    });

    test('跨度溢出表格边界时被钳制', () {
      final c = ctx();
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A', rowSpan: 99), const CellSpec('B')],
          <CellSpec>[const CellSpec('C')],
        ]),
        context: c,
      );
      expect(grid.cellAt(0, 0).rowSpan, 2);
      expect(countOf(c, ParseWarningKind.spanOverflow), 1);
    });

    test('thead / tbody / tfoot 按文档顺序贡献行', () {
      final html =
          '<table>'
          '<thead><tr><td>H</td></tr></thead>'
          '<tbody><tr><td>B</td></tr></tbody>'
          '<tfoot><tr><td>F</td></tr></tfoot>'
          '</table>';
      final grid = TableGrid.from(parseHtmlDocument(html).querySelector('table')!);
      expect(grid.rowCount, 3);
      expect(grid.cellAt(0, 0).element!.text, 'H');
      expect(grid.cellAt(1, 0).element!.text, 'B');
      expect(grid.cellAt(2, 0).element!.text, 'F');
    });

    test('隐式 tbody：裸 tr 也能成行', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A'), const CellSpec('B')],
        ], tbody: false),
      );
      expect(grid.rowCount, 1);
      expect(grid.cellAt(0, 0).element!.text, 'A');
    });

    test('caption 与 colgroup 不产生幽灵行', () {
      final grid = TableGrid.from(
        buildTable(
          <List<CellSpec>>[
            <CellSpec>[const CellSpec('A'), const CellSpec('B')],
          ],
          extraInside:
              '<caption>2025 学年课表</caption>'
              '<colgroup><col span="2"></colgroup>',
        ),
      );
      expect(grid.rowCount, 1);
      expect(grid.columnCount, 2);
    });

    test('空表不抛异常', () {
      final grid = TableGrid.from(buildTable(const <List<CellSpec>>[]));
      expect(grid.rowCount, 0);
      expect(grid.isEmpty, isTrue);
      expect(grid.originCells, isEmpty);
    });
  });

  group('TableGrid.transposed', () {
    test('行列互换，rowspan 变 colspan，宿主引用保持一致', () {
      final grid = TableGrid.from(
        buildTable(<List<CellSpec>>[
          <CellSpec>[const CellSpec('A', rowSpan: 2), const CellSpec('B')],
          <CellSpec>[const CellSpec('C')],
        ]),
      );
      final t = grid.transposed();
      expect(t.rowCount, 2);
      expect(t.columnCount, 2);
      final movedOrigin = t.cellAt(0, 0);
      expect(movedOrigin.isOrigin, isTrue);
      expect(movedOrigin.element!.text, 'A');
      expect(movedOrigin.colSpan, 2);
      expect(movedOrigin.rowSpan, 1);
      expect(t.cellAt(0, 1).isSpanned, isTrue);
      expect(t.cellAt(0, 1).origin, same(movedOrigin));
      expect(t.cellAt(1, 1).element!.text, 'C');
    });

    test('转置两次回到原状', () {
      final grid = TableGrid.from(buildPlainTable(3, 4));
      final back = grid.transposed().transposed();
      expect(back.rowCount, 3);
      expect(back.columnCount, 4);
      expect(back.cellAt(2, 3).element!.text, 'r2c3');
    });
  });

  test('100x20 压力用例：单遍扫描，不退化', () {
    final grid = TableGrid.from(buildPlainTable(100, 20));
    expect(grid.rowCount, 100);
    expect(grid.columnCount, 20);
    expect(grid.originCells.length, 2000);
  });
}
