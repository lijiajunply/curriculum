# 测试样本

这里的每个用例由**两个文件**组成，`registerFixtureSuites()` 会自动发现并生成测试：

```
test/fixtures/<适配器目录名>/<用例名>.html
test/fixtures/<适配器目录名>/<用例名>.expected.json
```

目录名大写、并把 `-` 换成 `_` 之后，应当是某个适配器 id 的前缀。
例如 `standard_grid/` → `STANDARD_GRID_01`。

## 投放一个真实教务系统样本

1. 在浏览器里打开课表页，**另存为** HTML（或从开发者工具复制 `document.documentElement.outerHTML`），
   存成 `test/fixtures/_pending/<校名>/sample.html`。
2. 跑一次看看解析器读出了什么：

   ```bash
   dart run example/main.dart test/fixtures/_pending/<校名>/sample.html
   ```

   它会打印适配器、每门课，以及一份诊断报告。
3. **人工核对**输出，重点看三处最容易出错的地方：
   - 跨行单元格（`rowspan`）的 `endSection` 是否正确；
   - 单双周是否被正确展开成整数列表；
   - 同一个格子里有多门课时，是否被正确拆成多条而不是被均分节次。
4. 核对无误后，把输出存成期望值并移出 `_pending/`：

   ```bash
   mkdir -p test/fixtures/<适配器目录名>
   mv test/fixtures/_pending/<校名>/sample.html test/fixtures/<适配器目录名>/basic.html
   dart run example/main.dart test/fixtures/<适配器目录名>/basic.html --json > /tmp/out.json
   # 用 /tmp/out.json 里的 courses 组装 test/fixtures/<适配器目录名>/basic.expected.json
   ```

`_pending/` 下的样本只做宽松断言（不抛异常、且有课程或诊断），所以拿到样本的
**当下**就能提交，之后再补期望值。

## 注意

- `.html` 里不要包含真实师生姓名与学号；样本入库前请脱敏。
- 期望值文件只需要提供 `courses` 数组的比对内容，适配器与诊断由测试自己校验。
