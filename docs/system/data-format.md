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
            ├── mesh.obj           # 統合メッシュ (Wavefront OBJ, LiDAR 取得時のみ)
            ├── points.ply         # 色付き点群 (PLY binary, 深度取得時のみ)
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
      "directoryName": "550e8400-e29b-41d4-a716-446655440000",
      "meshVertexCount": 48213,
      "meshFaceCount": 91024
    }
  ]
}
```

## metadata.json

`ScanSession` の Codable シリアライズと同一構造。

`meshVertexCount` / `meshFaceCount` は統合メッシュの規模を表す任意フィールドで、
メッシュを取得できなかったセッション（LiDAR 非対応など）や v1.0 以前のセッションでは省略される。

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
- **座標系**: 右手系。スキャン開始時の **縦持ち（ポートレート）表示** を基準に定義する

| 軸 | 向き |
|---|---|
| +X | 画面右方向 |
| +Y | 画面上方向（縦持ちでは概ね鉛直上向き） |
| +Z | 画面手前（カメラの後方。撮影方向は -Z） |

ARKit の `ARCamera.transform` はランドスケープ基準（+X が画面下、+Y が画面右）のため、
Z 軸まわりに -90° 回転させて上記の基準へ揃えている
(`CoordinateSystem.portraitAlignment`、ADR-010)。

このためスキャン開始フレームの `quaternion` は単位クォータニオンではなく、
Z 軸まわり -90° の回転（`[0, 0, -0.7071, 0.7071]`）になる。`translation` は原点 `[0, 0, 0]`。

> **互換性**: v1.1 以前に保存したセッションは、ARKit カメラ座標系（横倒し）が
> そのまま相対座標系になっている。

## _color.jpg

- 形式: JPEG (品質 90%)
- 解像度: デバイスと設定に依存 (通常 1920×1440)
- カラースペース: sRGB
- 内容: RGB フレーム (YCbCr → CIImage → CGImage → JPEG 変換)
- **向き**: ピクセル配列はセンサ基準（横長）のまま。縦持ち撮影に合わせて
  EXIF Orientation = 6 (`UIImage.Orientation.right` / 時計回り 90°) を付与する

`poses.json` の内部パラメータ (`fx`, `fy`, `cx`, `cy`) は EXIF 適用前の
センサ基準ピクセル座標に対応する。後処理でピクセルを扱う際は EXIF を適用せずに読み込む。

```python
from PIL import Image

# EXIF を無視してセンサ基準で読む（内部パラメータと整合する）
color = Image.open(path)

# 正立させて表示したい場合
from PIL import ImageOps
upright = ImageOps.exif_transpose(color)
```

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

## mesh.obj

スキャン中に ARKit が生成したシーン再構成メッシュ (`ARMeshAnchor`) を統合した
Wavefront OBJ ファイル。

```
# iMappingPro mesh export
# vertices: 48213
# faces: 91024
o iMappingProMesh
v 0.1234 -0.0421 1.9832
...
vn 0.0000 1.0000 0.0000
...
f 1//1 2//2 3//3
```

- 座標系: `poses.json` と同じ「スキャン開始地点を原点とする相対座標系」(ARKit 右手系・Y 軸上向き、単位はメートル)
- 頂点インデックス: OBJ 仕様どおり 1 始まり
- 法線: 取得できた場合のみ `vn` として出力され、面は `f v//vn` 形式になる
- 色情報は含まれない（色付きで扱いたい場合は `points.ply` を使う）

MeshLab・CloudCompare・Open3D・trimesh などで直接読み込める。

```python
import trimesh

mesh = trimesh.load(session_dir / "mesh.obj")
print(mesh.vertices.shape, mesh.faces.shape)

# 点群として扱う場合
points = mesh.vertices
```

## points.ply

RGB フレームと深度マップから生成した色付き点群 (PLY binary little endian)。
ARKit のシーン再構成メッシュは色情報を持たないため、その代替として保存する。

```
ply
format binary_little_endian 1.0
comment iMappingPro colored point cloud
element vertex 198432
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
end_header
<15 bytes * vertex count>
```

- 座標系: `poses.json` と同じ相対座標系（メートル）
- 生成条件: 深度マップを 40 フレーム以内・約 20 万点以内へ間引き、深度 0.1〜5.0 m のみ採用
- 色: 同一フレームのカラー画像を同一 FOV とみなして正規化座標でサンプル
- MeshLab・CloudCompare・Open3D (`o3d.io.read_point_cloud`) などでそのまま読める

## ZIP ダウンロード

履歴詳細画面のダウンロードメニューからは以下を書き出せる。

| メニュー | 内容 |
|---|---|
| セッション一式 (ZIP) | セッションディレクトリ全体（`metadata.json` / `poses.json` / `mesh.obj` / `points.ply` / `frames/`）|
| メッシュ (OBJ) | `mesh.obj` のみ |
| 色付き点群 (PLY) | `points.ply` のみ |
| 姿勢データ (poses.json) | `poses.json` のみ |

ZIP は `NSFileCoordinator(readingItemAt:options:.forUploading)` で生成され、
一時ディレクトリ上に `<セッション名>.zip` として作られる（ファイル名は安全な文字へサニタイズされる）。

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
