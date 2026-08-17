from __future__ import annotations

import csv
import os
import queue
import sys
import threading
import traceback
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

from production_flasher.core import (
    EsptoolBackend,
    ProductionError,
    VERSION,
    candidate_ports,
    localized,
    require_single_port,
    run_production,
    verify_images,
)


def application_dir() -> Path:
    return Path(sys.executable if getattr(sys, "frozen", False) else __file__).resolve().parent


def firmware_dir() -> Path:
    override = os.environ.get("MAURYA_FIRMWARE_DIR")
    if override:
        return Path(override).resolve()
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return base / "firmware"


def log_dir() -> Path:
    preferred = application_dir() / "logs"
    try:
        preferred.mkdir(parents=True, exist_ok=True)
        return preferred
    except OSError:
        fallback = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "MauryaFlasher" / "logs"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


class MauryaFlasherApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.events: queue.Queue[tuple] = queue.Queue()
        self.running = False
        self.port = tk.StringVar(value=localized("未检测", "未検出"))
        self.status = tk.StringVar(value=localized(
            "请连接一块Maurya控制板",
            "Mauryaコントロール基板を1台接続してください",
        ))
        self.detail = tk.StringVar(value="")
        self.mac = tk.StringVar(value="-")
        self.flash = tk.StringVar(value="-")
        self.progress = tk.IntVar(value=0)
        self._build_ui()
        self.refresh_ports()
        self.root.after(80, self._poll_events)

    def _build_ui(self) -> None:
        self.root.title(localized(
            f"Maurya 一键量产烧录工具 v{VERSION}",
            f"Maurya 日本語版 書き込みツール v{VERSION}",
        ))
        self.root.geometry("640x465")
        self.root.minsize(600, 440)
        self.root.configure(bg="#0d111b")
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame", background="#0d111b")
        style.configure("Card.TFrame", background="#171d2a")
        style.configure("TLabel", background="#171d2a", foreground="#eaf0ff", font=("Yu Gothic UI", 10))
        style.configure("Title.TLabel", background="#0d111b", foreground="#ffffff", font=("Yu Gothic UI", 22, "bold"))
        style.configure("Status.TLabel", background="#171d2a", foreground="#8fb8ff", font=("Yu Gothic UI", 14, "bold"))
        style.configure("TButton", font=("Yu Gothic UI", 11, "bold"), padding=10)
        style.configure("Horizontal.TProgressbar", troughcolor="#252c3b", background="#3378ff")

        outer = ttk.Frame(self.root, padding=24)
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text=localized("Maurya 量产烧录", "Maurya ファームウェア書き込み"), style="Title.TLabel").pack(anchor="w")
        ttk.Label(outer, text=localized(
            f"多语言固件 v{VERSION} · ESP32-C3 · 4 MB",
            f"日本語専用版 v{VERSION} · ESP32-C3 · 4 MB",
        ), background="#0d111b", foreground="#8791a8").pack(anchor="w", pady=(3, 18))

        card = ttk.Frame(outer, style="Card.TFrame", padding=20)
        card.pack(fill="both", expand=True)
        grid = ttk.Frame(card, style="Card.TFrame")
        grid.pack(fill="x")
        for row, (name, variable) in enumerate(((localized("串口", "シリアルポート"), self.port), ("MAC", self.mac), (localized("Flash", "フラッシュ"), self.flash))):
            ttk.Label(grid, text=name, foreground="#8791a8").grid(row=row, column=0, sticky="w", pady=4)
            ttk.Label(grid, textvariable=variable).grid(row=row, column=1, sticky="w", padx=(24, 0), pady=4)
        grid.columnconfigure(1, weight=1)

        ttk.Separator(card).pack(fill="x", pady=17)
        ttk.Label(card, textvariable=self.status, style="Status.TLabel").pack(anchor="w")
        ttk.Label(card, textvariable=self.detail, foreground="#aeb8cc", wraplength=540).pack(anchor="w", pady=(5, 14))
        ttk.Progressbar(card, variable=self.progress, maximum=100).pack(fill="x")

        buttons = ttk.Frame(card, style="Card.TFrame")
        buttons.pack(fill="x", pady=(20, 0))
        self.refresh_button = ttk.Button(buttons, text=localized("刷新设备", "デバイスを再検出"), command=self.refresh_ports)
        self.refresh_button.pack(side="left")
        self.flash_button = ttk.Button(buttons, text=localized("一键烧录", "書き込み開始"), command=self.start)
        self.flash_button.pack(side="right")
        ttk.Label(card, text=localized(
            "注意：将整片擦除，当前设置无法恢复。",
            "注意：フラッシュ全体を消去するため、現在の設定は復元できません。",
        ), foreground="#f0aa66").pack(anchor="w", pady=(18, 0))

    def refresh_ports(self) -> None:
        found = candidate_ports()
        if len(found) == 1:
            self.port.set(found[0])
            self.status.set(localized("准备就绪", "準備ができました"))
            self.detail.set(localized(
                "点击“一键烧录”开始整片擦除和烧录",
                "「書き込み開始」を押すと、全消去と書き込みを開始します",
            ))
        elif not found:
            self.port.set(localized("未检测", "未検出"))
            self.status.set(localized("未找到设备", "デバイスが見つかりません"))
            self.detail.set(localized(
                "请连接一块USB VID 303A的ESP32-C3控制板",
                "USB VID 303AのESP32-C3コントロール基板を1台接続してください",
            ))
        else:
            self.port.set(", ".join(found))
            self.status.set(localized("检测到多个设备", "複数のデバイスが見つかりました"))
            self.detail.set(localized(
                "请只连接一块控制板，然后刷新设备",
                "基板を1台だけ接続し、再検出してください",
            ))

    def start(self) -> None:
        if self.running:
            return
        try:
            port = require_single_port()
        except ProductionError as exc:
            messagebox.showerror(exc.stage, str(exc))
            self.refresh_ports()
            return
        if not messagebox.askyesno(
            localized("确认整片擦除", "全消去の確認"),
            localized(f"将整片擦除并烧录{port}，是否继续？", f"{port}を全消去して書き込みます。続行しますか？"),
        ):
            return
        self.running = True
        self.flash_button.configure(state="disabled")
        self.refresh_button.configure(state="disabled")
        self.progress.set(0)
        self.mac.set("-")
        self.flash.set("-")
        threading.Thread(target=self._worker, args=(port,), daemon=True).start()

    def _worker(self, port: str) -> None:
        started = datetime.now()
        lines: list[str] = []

        def progress(stage: str, percent: int, message: str) -> None:
            stamp = datetime.now().strftime("%H:%M:%S")
            lines.append(f"[{stamp}] {stage}: {message}")
            self.events.put(("progress", stage, percent, message))

        result = None
        error = None
        backend = EsptoolBackend()
        try:
            result = run_production(port, firmware_dir(), backend, progress)
            self.events.put(("success", result))
        except Exception as exc:
            error = exc if isinstance(exc, ProductionError) else ProductionError(
                localized("意外错误", "予期しないエラー"), str(exc),
            )
            lines.append(traceback.format_exc())
            self.events.put(("failure", error))
        finally:
            lines.extend(backend.transcript)
            self._write_logs(started, port, result, backend.device_info, error, lines)

    @staticmethod
    def _write_logs(started, port, result, detected_device, error, lines) -> None:
        directory = log_dir()
        stamp = started.strftime("%Y%m%d-%H%M%S")
        device = result.device if result else detected_device
        mac = device.mac if device else "UNKNOWN"
        (directory / f"{stamp}-{mac.replace(':', '')}.log").write_text("\n".join(lines), encoding="utf-8")
        csv_path = directory / "production.csv"
        new_file = not csv_path.exists()
        with csv_path.open("a", newline="", encoding="utf-8-sig") as stream:
            writer = csv.writer(stream)
            if new_file:
                writer.writerow(("time", "result", "port", "mac", "flash_id", "version", "seconds", "failure_stage", "message"))
            writer.writerow((
                started.isoformat(timespec="seconds"), "PASS" if result else "FAIL", port,
                device.mac if device else "", device.flash_id if device else "", VERSION,
                f"{result.elapsed_seconds:.1f}" if result else "",
                error.stage if error else "", str(error) if error else "",
            ))

    def _poll_events(self) -> None:
        try:
            while True:
                event = self.events.get_nowait()
                if event[0] == "progress":
                    _, stage, percent, message = event
                    self.status.set(stage)
                    self.detail.set(message)
                    self.progress.set(percent)
                elif event[0] == "success":
                    result = event[1]
                    self.mac.set(result.device.mac)
                    self.flash.set(f"{result.device.flash_size} · ID {result.device.flash_id}")
                    self.status.set(localized("烧录成功", "書き込み完了"))
                    self.detail.set(localized(
                        f"应用已启动，Modbus验证通过（{result.elapsed_seconds:.1f}秒）",
                        f"アプリケーションが起動し、Modbus確認に成功しました（{result.elapsed_seconds:.1f}秒）",
                    ))
                    self.progress.set(100)
                    self.running = False
                    self.flash_button.configure(state="normal")
                    self.refresh_button.configure(state="normal")
                elif event[0] == "failure":
                    error = event[1]
                    self.status.set(localized("烧录失败", "書き込み失敗"))
                    self.detail.set(f"{error.stage}：{error}")
                    self.running = False
                    self.flash_button.configure(state="normal", text=localized("重新烧录", "再試行"))
                    self.refresh_button.configure(state="normal")
                    messagebox.showerror(localized(f"失败：{error.stage}", f"失敗：{error.stage}"), str(error))
        except queue.Empty:
            pass
        self.root.after(80, self._poll_events)


def main() -> None:
    if "--smoke-test" in sys.argv:
        verify_images(firmware_dir())
        return
    root = tk.Tk()
    MauryaFlasherApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
