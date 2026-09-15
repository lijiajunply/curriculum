import 'builtin/standard_grid_adapter.dart';
import 'builtin/xauat_adapter.dart';
import 'builtin/zhengfang_grid_adapter.dart';
import 'general_matrix_adapter.dart';
import 'school_adapter.dart';

/// 本库内置的适配器。
///
/// 顺序即注册顺序：专用适配器在前，启发式兜底在后。各校专属适配器会随真实样本
/// 逐步加入；宿主也可以把自己的适配器注册进 `SchoolAdapterRegistry`。
List<SchoolAdapter> buildBuiltinAdapters() => const <SchoolAdapter>[
  StandardGridAdapter(),
  ZhengfangGridAdapter(),
  XauatAdapter(),
  // 兜底适配器必须排在最后，且它的置信度被压到 0.1，只在无其它候选时生效。
  GeneralMatrixAdapter(),
];
