"""不依賴 torch、也不執行 pickle 內容，直接讀出 .pth 的張量形狀。

.pth 是 zip + pickle。pickle 天生可以在反序列化時執行任意程式碼，
而這些檔案來自 Discord 上的陌生人打包，所以這裡用 find_class 白名單：
只有 torch 的 rebuild 函式會被映射成「記錄形狀」的替身，
其餘 torch 符號回傳惰性 stub，非 torch 的一律拒絕。
全程沒有任何來自檔案的程式碼被執行。
"""

import pickle
import sys
import zipfile


class TensorInfo:
    def __init__(self, shape, dtype):
        self.shape = tuple(shape)
        self.dtype = dtype

    def __repr__(self):
        return f"T{self.shape}"


class Stub:
    """未知 torch 符號的替身——被引用可以，被呼叫也只回傳自己"""

    def __init__(self, name):
        self.name = name

    def __call__(self, *args, **kwargs):
        return self

    def __setstate__(self, state):
        pass   # BUILD 指令套到 stub 上時忽略，不還原任何狀態

    def __repr__(self):
        return f"<{self.name}>"


def rebuild_tensor(storage, storage_offset, size, stride, *rest):
    dtype = storage[1] if isinstance(storage, tuple) and len(storage) > 1 else "?"
    return TensorInfo(size, dtype)


class SafeUnpickler(pickle.Unpickler):
    ALLOWED = {
        ("torch._utils", "_rebuild_tensor_v2"): rebuild_tensor,
        ("torch._utils", "_rebuild_tensor"): rebuild_tensor,
        ("collections", "OrderedDict"): __import__("collections").OrderedDict,
        # numpy dtype 還原會用到，本身只是字串編碼，不具執行能力
        ("_codecs", "encode"): __import__("codecs").encode,
    }

    def find_class(self, module, name):
        key = (module, name)
        if key in self.ALLOWED:
            return self.ALLOWED[key]
        if module.startswith("torch") or module.startswith("numpy"):
            return Stub(f"{module}.{name}")
        raise pickle.UnpicklingError(f"拒絕載入 {module}.{name}")

    def persistent_load(self, pid):
        return tuple(pid) if isinstance(pid, (tuple, list)) else pid


def load(path):
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if n.endswith("data.pkl")]
        if not names:
            raise SystemExit(f"{path}: 找不到 data.pkl（不是 zip 格式的 .pth？）")
        with z.open(names[0]) as f:
            return SafeUnpickler(f).load()


def first_conv_in_channels(module_state):
    """第一層 Conv1d 的 weight 形狀是 (out, in, kernel)，in 就是 obs channel 數"""
    for key, val in module_state.items():
        if isinstance(val, TensorInfo) and len(val.shape) == 3:
            return key, val.shape
    return None, None


def last_linear_out(module_state):
    """最後一層 Linear 的 bias 長度 = 動作空間大小"""
    last = (None, None)
    for key, val in module_state.items():
        if isinstance(val, TensorInfo) and len(val.shape) == 1 and key.endswith("bias"):
            last = (key, val.shape)
    return last


for path in sys.argv[1:]:
    print(f"\n=== {path.split('/')[-1]} ===")
    try:
        state = load(path)
    except Exception as exc:
        print(f"  讀取失敗: {exc}")
        continue

    with zipfile.ZipFile(path) as z:
        prefix = z.namelist()[0].split("/")[0]
    print(f"  archive 名稱: {prefix}")
    if not hasattr(state, "keys"):
        print(f"  頂層型別: {type(state)}  {repr(state)[:200]}")
        continue
    print(f"  頂層鍵: {list(state.keys())}")

    cfg = state.get("config", {})
    control = cfg.get("control", {}) if isinstance(cfg, dict) else {}
    resnet = cfg.get("resnet", {}) if isinstance(cfg, dict) else {}
    print(f"  version={control.get('version')}  resnet={dict(resnet) if resnet else None}")

    brain = state.get("mortal")
    if isinstance(brain, dict):
        key, shape = first_conv_in_channels(brain)
        if shape:
            in_ch = shape[1]
            verdict = "三麻 (775)" if in_ch == 775 else "四麻 (1012)" if in_ch == 1012 else f"未知 ({in_ch})"
            print(f"  第一層 conv: {key} {shape}  → obs channels = {in_ch}  ★ {verdict}")

    dqn = state.get("current_dqn")
    if isinstance(dqn, dict):
        print("  DQN 各層:")
        for k, v in dqn.items():
            if isinstance(v, TensorInfo):
                print(f"    {k} {v.shape}")
