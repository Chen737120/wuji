import '../data/app_repository.dart' show MediaInput;

/// 保存前空间预检（规格 §8）：剩余空间 < 新附件总大小 → 需要 UI 层警告。
/// freeBytes 为 null（SAF 无法查询）时降级为不警告。
bool needsSpaceWarning(int? freeBytes, int incomingBytes) {
  if (freeBytes == null) return false;
  if (incomingBytes <= 0) return false;
  return freeBytes < incomingBytes;
}

/// 计算本次保存的新附件总字节数（表单内已去重）。
int incomingBytesOf(Iterable<MediaInput> inputs) =>
    inputs.fold(0, (a, m) => a + m.sizeBytes);
