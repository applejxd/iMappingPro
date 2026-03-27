# データフォーマット仕様

## ストレージ構造

```
Documents/
└── iMappingPro/
    ├── sessions.json              # セッション一覧インデックス
    └── sessions/
        └── <UUID>/
            ├── metadata.json      # セッション詳細
            ├── poses.json         # 全フレームの6DOF姿勢
            └── frames/
                ├── 000000_color.jpg    # RGB フレーム (JPEG)
                ├── 000000_depth.bin    # 深度マップ (Float32 binary)
                ├── 000000_conf.png     # 信頼度マップ (PNG grayscale)
                ├── 000001_color.jpg
                ...
```

## sessions.json

```json
{
  "version": 1,
  "sessions": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "リビングルーム",
      "createdAt": "2024-01-01T10:00:00Z",
      "frameCount": 150,
      "durationSeconds": 30.5,
      "directoryName": "550e8400-e29b-41d4-a716-446655440000"
    }
  ]
}
```

## metadata.json

`ScanSession` の Codable シリアライズと同一構造。

## poses.json

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "frame_count": 150,
  "frames": [
    {
      "index": 0,
      "timestamp": 0.0,
      "translation": [0.0, 0.0, 0.0],
      "quaternion": [0.0, 0.0, 0.0, 1.0],
      "intrinsics": {
        "fx": 1440.123,
        "fy": 1440.456,
        "cx": 960.0,
        "cy": 720.0
      },
      "image_size": { "width": 1920, "height": 1440 },
      "depth_size": { "width": 256, "height": 192 }
    },
    {
      "index": 1,
      "timestamp": 0.103,
      "translation": [0.052, -0.003, 0.012],
      "quaternion": [0.001, 0.012, 0.0, 0.9999],
      ...
    }
  ]
}
```

### 姿勢の定義

- **translation**: `[tx, ty, tz]` — 初期フレームを原点とした相対平行移動 (メートル)
- **quaternion**: `[qx, qy, qz, qw]` — simd_quatf の vector 形式 (ix, iy, iz, r)
- **座標系**: ARKit 右手系 (Y軸上向き)

## _color.jpg

- 形式: JPEG (品質 90%)
- 解像度: デバイスと設定に依存 (通常 1920×1440)
- カラースペース: sRGB
- 内容: RGB フレーム (YCbCr → CIImage → CGImage → JPEG 変換)

## _depth.bin

バイナリフォーマット:

```
Offset  Size    Type        Description
0       4       UInt32 LE   width  (ピクセル幅)
4       4       UInt32 LE   height (ピクセル高さ)
8       W*H*4   Float32 LE  深度値 (メートル, row-major)
```

- 有効範囲: 0.1 〜 10.0 m (NaN は無効値)
- 0.0 は深度未測定を意味する

## _conf.png

- 形式: PNG グレースケール (8-bit)
- 解像度: 深度マップと同じ (通常 256×192)
- ピクセル値:
  - 0: ARConfidenceLevel.low
  - 127: ARConfidenceLevel.medium
  - 255: ARConfidenceLevel.high (※実装では 127 を使用)

## Python による読み込みサンプル

```python
import json
import numpy as np
from PIL import Image
from pathlib import Path

session_dir = Path("sessions/550e8400-.../")

# 姿勢の読み込み
with open(session_dir / "poses.json") as f:
    poses = json.load(f)

for frame in poses["frames"]:
    idx = frame["index"]
    t = np.array(frame["translation"])    # [tx, ty, tz]
    q = np.array(frame["quaternion"])     # [qx, qy, qz, qw]
    
    # RGB 画像
    color = Image.open(session_dir / "frames" / f"{idx:06d}_color.jpg")
    
    # 深度マップ
    depth_path = session_dir / "frames" / f"{idx:06d}_depth.bin"
    with open(depth_path, "rb") as f:
        w = int.from_bytes(f.read(4), "little")
        h = int.from_bytes(f.read(4), "little")
        depth = np.frombuffer(f.read(w * h * 4), dtype=np.float32).reshape(h, w)
    
    print(f"Frame {idx}: t={t}, depth shape={depth.shape}")
```

## TUM RGB-D 形式へのエクスポート

研究用途で TUM RGB-D データセット形式に変換する場合:

```python
# rgb.txt
# timestamp filename
# depth.txt  
# timestamp filename
# groundtruth.txt
# timestamp tx ty tz qx qy qz qw

with open("rgb.txt", "w") as f_rgb, \
     open("depth.txt", "w") as f_depth, \
     open("groundtruth.txt", "w") as f_gt:
    for frame in poses["frames"]:
        idx = frame["index"]
        ts = frame["timestamp"]
        t = frame["translation"]
        q = frame["quaternion"]
        f_rgb.write(f"{ts:.6f} rgb/{idx:06d}.jpg\n")
        f_depth.write(f"{ts:.6f} depth/{idx:06d}.png\n")
        f_gt.write(f"{ts:.6f} {t[0]} {t[1]} {t[2]} {q[0]} {q[1]} {q[2]} {q[3]}\n")
```
