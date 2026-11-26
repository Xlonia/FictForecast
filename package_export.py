"""导出打包脚本（m3.11 批复：保留 exe，数据外置——发布版也能改气候表）。

用法：
    python -I package_export.py            # 导出 zip 并把数据追加进包
    python -I package_export.py --skip-export   # 复用已有 zip，只刷新 data/

产物：<工程上级>/_snapshots/幻想气象局 FictForecast.zip（路径取自 export_presets.cfg 的预设），
    解压后：FictForecast.exe + FictForecast.pck + data/
    data/ 下：Climate/*.csv、Worlds/*.json、Cities/*.json、Localization/*、Maps/**

说明：
    · 预设已是 embed_pck=false，且气候表/json/yaml 不是引擎资源——本就不进 pck；
      本脚本把数据作为 data/ 追加进 zip，解压即用。
    · 用户不装 Godot 就能改数据：exe 菜单「设置编辑器」→ 自动以 --ff-editor 模式拉起自身
      （同进程换场景成编辑器，无递归）；数据根 = exe 同级 data/，--data-dir=<路径> 可指向别处。
    · .gd/.tscn 导出后是只读 token（script_export_mode=2）——能改的只有数据，方案天花板即此。
    · 开发环境（godot --path 工程跑）数据根仍是 res://，行为不变。
"""
import json
import os
import shutil
import subprocess
import sys
import zipfile

PROJ = os.path.dirname(os.path.abspath(__file__))
GODOT = os.environ.get("GODOT_EXE",
                       r"D:\godot\Godot_v4.3-stable_mono_win64\Godot_v4.7.2-stable_win64.exe")
PRESET = "Windows Desktop"
ZIP_PATH = os.path.normpath(os.path.join(PROJ, "..", "_snapshots", "幻想气象局 FictForecast.zip"))
DATA_EXTS = {".csv": "Climate", ".json": "Worlds"}


def run_export():
    os.makedirs(os.path.dirname(ZIP_PATH), exist_ok=True)
    cmd = [GODOT, "--headless", "--path", PROJ, "--export-release", PRESET, ZIP_PATH]
    print(">>", " ".join('"%s"' % c if " " in c else c for c in cmd))
    r = subprocess.run(cmd, cwd=PROJ)
    if r.returncode != 0 or not os.path.exists(ZIP_PATH):
        sys.exit("导出失败（exit=%d）——检查导出模板（%%APPDATA%%/Godot/export_templates/4.7.2.stable）" % r.returncode)
    print("导出完成：", ZIP_PATH)


def collect_data(tmp_dir):
    """把要外置的数据收进 tmp_dir/data，返回 {说明: 数量}。"""
    counts = {}

    def copy_only(rel, exts):
        n = 0
        src_root = os.path.join(PROJ, rel)
        dst_root = os.path.join(tmp_dir, "data", rel)
        if not os.path.isdir(src_root):
            return 0
        os.makedirs(dst_root, exist_ok=True)
        for f in sorted(os.listdir(src_root)):
            if os.path.splitext(f)[1].lower() in exts:
                shutil.copy2(os.path.join(src_root, f), os.path.join(dst_root, f))
                n += 1
        return n

    counts["Climate/*.csv"] = copy_only("Climate", {".csv"})
    counts["Worlds/*.json"] = copy_only("Worlds", {".json"})
    counts["Cities/*.json"] = copy_only("Cities", {".json"})
    counts["Localization/*"] = copy_only("Localization", {".yaml", ".json"})
    src_maps = os.path.join(PROJ, "Maps")
    if os.path.isdir(src_maps):
        n = 0
        for root, _dirs, files in os.walk(src_maps):
            rel = os.path.relpath(root, src_maps)
            for f in files:
                dst = os.path.join(tmp_dir, "data", "Maps", rel, f)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(os.path.join(root, f), dst)
                n += 1
        counts["Maps/**"] = n
    return counts


def append_data(tmp_dir):
    added = 0
    with zipfile.ZipFile(ZIP_PATH, "a", compression=zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(tmp_dir):
            for f in files:
                full = os.path.join(root, f)
                arc = os.path.relpath(full, tmp_dir).replace("\\", "/")
                z.write(full, arc)
                added += 1
    return added


def main():
    skip = "--skip-export" in sys.argv
    if skip and not os.path.exists(ZIP_PATH):
        sys.exit("未找到已导出的 zip：%s（先不带 --skip-export 跑一次）" % ZIP_PATH)
    tmp_dir = os.path.join(os.environ.get("TEMP", "/tmp"), "ff_package_data")
    if os.path.isdir(tmp_dir):
        shutil.rmtree(tmp_dir)
    os.makedirs(tmp_dir, exist_ok=True)
    if not skip:
        run_export()
    counts = collect_data(tmp_dir)
    print("数据收集完成：")
    for k, v in counts.items():
        print("   %-18s %d 个文件" % (k, v))
    added = append_data(tmp_dir)
    shutil.rmtree(tmp_dir, ignore_errors=True)
    size = os.path.getsize(ZIP_PATH)
    print("已把 %d 个数据文件以 data/ 追加进 zip：%s（%.1f MB）" % (added, ZIP_PATH, size / 1048576.0))
    print("\n打包完成。把这个 zip 发给别人，解压即用：")
    print("  · exe 启动主程序；菜单「设置编辑器」→ 子进程带 --ff-editor 自启编辑器（无递归）")
    print("  · 数据在解压后的 data/ 下，记事本/本编辑器直接改；--data-dir=<路径> 可指向别处")
    print("  · 开发者合并：别人改好的 data/ 下的 yaml/json/csv 直接拷回工程目录即可")


if __name__ == "__main__":
    main()
