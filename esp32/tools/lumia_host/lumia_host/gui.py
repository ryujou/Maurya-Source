from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from .client import GroupSnapshot, LumiaSerialClient
from .protocol import INNER_MODE_LABELS, REG, SCENE_MODE_LABELS


class LumiaHostApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Lumia ESP32 Host Tool")
        self.client = LumiaSerialClient()

        self.port_var = tk.StringVar()
        self.addr_var = tk.IntVar(value=1)
        self.status_var = tk.StringVar(value="Disconnected")
        self.log_var = tk.StringVar(value="Ready")
        self.temp_var = tk.StringVar(value="--.- C")
        self.vdda_var = tk.StringVar(value="---- mV")
        self.diag_var = tk.StringVar(value="rx=0 overflow=0 tx_drop=0 parse=0")

        self.scene_mode_var = tk.StringVar(value="1 - Static")
        self.scene_param_var = tk.IntVar(value=80)
        self.bri_var = tk.IntVar(value=255)
        self.gain_r_var = tk.IntVar(value=255)
        self.gain_g_var = tk.IntVar(value=176)
        self.gain_b_var = tk.IntVar(value=240)

        self.group_vars: list[dict[str, tk.Variable]] = []

        self._build()
        self.refresh_ports()

    def _build(self) -> None:
        root = self.root
        root.columnconfigure(0, weight=1)

        connection = ttk.LabelFrame(root, text="Connection")
        connection.grid(row=0, column=0, sticky="ew", padx=8, pady=8)
        connection.columnconfigure(1, weight=1)
        ttk.Label(connection, text="Port").grid(row=0, column=0, padx=4, pady=4)
        self.port_combo = ttk.Combobox(connection,
                                       textvariable=self.port_var,
                                       state="readonly")
        self.port_combo.grid(row=0, column=1, sticky="ew", padx=4, pady=4)
        ttk.Button(connection, text="Refresh", command=self.refresh_ports).grid(row=0, column=2, padx=4, pady=4)
        ttk.Label(connection, text="Addr").grid(row=0, column=3, padx=4, pady=4)
        ttk.Spinbox(connection, from_=1, to=247, textvariable=self.addr_var, width=6).grid(row=0, column=4, padx=4, pady=4)
        ttk.Button(connection, text="Connect", command=self.connect).grid(row=0, column=5, padx=4, pady=4)
        ttk.Button(connection, text="Disconnect", command=self.disconnect).grid(row=0, column=6, padx=4, pady=4)
        ttk.Label(connection, textvariable=self.status_var).grid(row=1, column=0, columnspan=7, sticky="w", padx=4, pady=4)

        scene = ttk.LabelFrame(root, text="Scene Control")
        scene.grid(row=1, column=0, sticky="ew", padx=8, pady=8)
        for column in range(4):
            scene.columnconfigure(column, weight=1)
        ttk.Label(scene, text="Scene Mode").grid(row=0, column=0, padx=4, pady=4, sticky="w")
        self.scene_combo = ttk.Combobox(
            scene,
            textvariable=self.scene_mode_var,
            values=[f"{key} - {value}" for key, value in SCENE_MODE_LABELS.items()],
            state="readonly",
        )
        self.scene_combo.grid(row=0, column=1, sticky="ew", padx=4, pady=4)
        ttk.Label(scene, text="Scene Speed").grid(row=0, column=2, padx=4, pady=4, sticky="w")
        ttk.Spinbox(scene, from_=0, to=255, textvariable=self.scene_param_var, width=8).grid(row=0, column=3, padx=4, pady=4)
        ttk.Button(scene, text="Apply Scene", command=self.apply_scene).grid(row=1, column=0, padx=4, pady=4)
        ttk.Button(scene, text="Refresh All", command=self.refresh_state).grid(row=1, column=1, padx=4, pady=4)

        global_led = ttk.LabelFrame(root, text="Global LED")
        global_led.grid(row=2, column=0, sticky="ew", padx=8, pady=8)
        for column in range(5):
            global_led.columnconfigure(column, weight=1)
        self._add_scale(global_led, "Brightness", self.bri_var, 255, 0)
        self._add_scale(global_led, "Gain R", self.gain_r_var, 255, 1)
        self._add_scale(global_led, "Gain G", self.gain_g_var, 255, 2)
        self._add_scale(global_led, "Gain B", self.gain_b_var, 255, 3)
        ttk.Button(global_led, text="Apply Global", command=self.apply_global).grid(row=4, column=0, padx=4, pady=4)
        ttk.Button(global_led, text="Apply All", command=self.apply_all).grid(row=4, column=1, padx=4, pady=4)

        groups = ttk.LabelFrame(root, text="Per Group Inner")
        groups.grid(row=3, column=0, sticky="ew", padx=8, pady=8)
        for column in range(7):
            groups.columnconfigure(column, weight=1)

        headers = ("Group", "Inner Mode", "Hue", "Sat", "Val", "Inner Param", "Apply")
        for column, header in enumerate(headers):
            ttk.Label(groups, text=header).grid(row=0, column=column, padx=4, pady=4, sticky="w")

        for group_index in range(REG.GROUP_COUNT):
            inner_mode_var = tk.StringVar(value="1 - Steady")
            hue_var = tk.IntVar(value=30)
            sat_var = tk.IntVar(value=255)
            val_var = tk.IntVar(value=255)
            inner_param_var = tk.IntVar(value=255)
            self.group_vars.append(
                {
                    "inner_mode": inner_mode_var,
                    "hue": hue_var,
                    "sat": sat_var,
                    "val": val_var,
                    "inner_param": inner_param_var,
                }
            )
            ttk.Label(groups, text=f"G{group_index + 1}").grid(row=group_index + 1, column=0, padx=4, pady=4, sticky="w")
            ttk.Combobox(
                groups,
                textvariable=inner_mode_var,
                values=[f"{key} - {value}" for key, value in INNER_MODE_LABELS.items()],
                state="readonly",
                width=12,
            ).grid(row=group_index + 1, column=1, padx=4, pady=4, sticky="ew")
            ttk.Spinbox(groups, from_=0, to=359, textvariable=hue_var, width=6).grid(row=group_index + 1, column=2, padx=4, pady=4)
            ttk.Spinbox(groups, from_=0, to=255, textvariable=sat_var, width=6).grid(row=group_index + 1, column=3, padx=4, pady=4)
            ttk.Spinbox(groups, from_=0, to=255, textvariable=val_var, width=6).grid(row=group_index + 1, column=4, padx=4, pady=4)
            ttk.Spinbox(groups, from_=0, to=255, textvariable=inner_param_var, width=6).grid(row=group_index + 1, column=5, padx=4, pady=4)
            ttk.Button(groups, text="Apply", command=lambda idx=group_index: self.apply_group(idx)).grid(row=group_index + 1, column=6, padx=4, pady=4)

        batch = ttk.LabelFrame(root, text="Batch Actions")
        batch.grid(row=4, column=0, sticky="ew", padx=8, pady=8)
        ttk.Button(batch, text="Copy Group1 -> All", command=self.copy_group1_to_all).grid(row=0, column=0, padx=4, pady=4)
        ttk.Button(batch, text="Set All Groups Same", command=self.set_all_groups_same).grid(row=0, column=1, padx=4, pady=4)

        telemetry = ttk.LabelFrame(root, text="Telemetry")
        telemetry.grid(row=5, column=0, sticky="ew", padx=8, pady=8)
        ttk.Label(telemetry, text="Temperature").grid(row=0, column=0, padx=4, pady=4, sticky="w")
        ttk.Label(telemetry, textvariable=self.temp_var).grid(row=0, column=1, padx=4, pady=4, sticky="w")
        ttk.Label(telemetry, text="VDDA").grid(row=0, column=2, padx=4, pady=4, sticky="w")
        ttk.Label(telemetry, textvariable=self.vdda_var).grid(row=0, column=3, padx=4, pady=4, sticky="w")
        ttk.Label(telemetry, textvariable=self.diag_var).grid(row=1, column=0, columnspan=3, padx=4, pady=4, sticky="w")
        ttk.Button(telemetry, text="Clear Diag", command=self.clear_diag).grid(row=1, column=3, padx=4, pady=4)

        ttk.Label(root, textvariable=self.log_var).grid(row=6, column=0, sticky="ew", padx=8, pady=8)

    def _add_scale(self,
                   parent: ttk.LabelFrame,
                   label: str,
                   variable: tk.IntVar,
                   maximum: int,
                   row: int) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, padx=4, pady=4, sticky="w")
        ttk.Scale(parent, from_=0, to=maximum, variable=variable).grid(
            row=row, column=1, columnspan=3, sticky="ew", padx=4, pady=4
        )
        ttk.Spinbox(parent, from_=0, to=maximum, textvariable=variable, width=6).grid(
            row=row, column=4, padx=4, pady=4
        )

    def _require_client(self) -> LumiaSerialClient:
        if not self.client.is_connected:
            raise RuntimeError("not connected")
        return self.client

    def refresh_ports(self) -> None:
        ports = self.client.list_ports()
        self.port_combo["values"] = ports
        if ports and not self.port_var.get():
            self.port_var.set(ports[0])
        self.log_var.set(f"Found {len(ports)} serial ports")

    def connect(self) -> None:
        try:
            if not self.port_var.get():
                raise RuntimeError("select a serial port first")
            self.client.connect(self.port_var.get())
            self.status_var.set(f"Connected: {self.port_var.get()}")
            self.refresh_state()
        except Exception as exc:
            messagebox.showerror("Connect Failed", str(exc))

    def disconnect(self) -> None:
        self.client.disconnect()
        self.status_var.set("Disconnected")
        self.log_var.set("Disconnected")

    def refresh_state(self) -> None:
        try:
            snapshot = self._require_client().read_snapshot(self.addr_var.get())
            self.scene_mode_var.set(
                f"{snapshot.scene_mode} - {snapshot.scene_mode_label}"
            )
            self.scene_param_var.set(snapshot.scene_param)
            self.bri_var.set(snapshot.global_brightness)
            self.gain_r_var.set(snapshot.gain_r)
            self.gain_g_var.set(snapshot.gain_g)
            self.gain_b_var.set(snapshot.gain_b)
            self.temp_var.set(f"{snapshot.temp_c_x100 / 100:.1f} C")
            self.vdda_var.set(f"{snapshot.vdda_mv} mV")
            self.diag_var.set(
                f"rx={snapshot.rx_count} overflow={snapshot.rx_overflow} "
                f"tx_drop={snapshot.tx_drop} parse={snapshot.parse_error}"
            )
            self._load_group_controls(snapshot.groups)
            self.log_var.set("Runtime state refreshed")
        except Exception as exc:
            messagebox.showerror("Read Failed", str(exc))

    def _load_group_controls(self, groups: list[GroupSnapshot]) -> None:
        for index, group in enumerate(groups):
            vars_for_group = self.group_vars[index]
            vars_for_group["inner_mode"].set(
                f"{group.inner_mode} - {group.inner_mode_label}"
            )
            vars_for_group["hue"].set(group.hue)
            vars_for_group["sat"].set(group.sat)
            vars_for_group["val"].set(group.val)
            vars_for_group["inner_param"].set(group.inner_param)

    def apply_scene(self) -> None:
        try:
            client = self._require_client()
            addr = self.addr_var.get()
            scene_mode = int(self.scene_mode_var.get().split(" - ", 1)[0])
            client.write_multiple(
                addr,
                REG.SCENE_MODE,
                [scene_mode, self.scene_param_var.get()],
            )
            self.log_var.set("Scene updated")
        except Exception as exc:
            messagebox.showerror("Write Failed", str(exc))

    def apply_global(self) -> None:
        try:
            client = self._require_client()
            addr = self.addr_var.get()
            client.write_multiple(
                addr,
                REG.LED_GLOBAL_BRI,
                [
                    self.bri_var.get(),
                    self.gain_r_var.get(),
                    self.gain_g_var.get(),
                    self.gain_b_var.get(),
                ],
            )
            self.log_var.set("Global LED settings updated")
        except Exception as exc:
            messagebox.showerror("Write Failed", str(exc))

    def _group_payload(self, group_index: int) -> list[int]:
        vars_for_group = self.group_vars[group_index]
        return [
            int(str(vars_for_group["inner_mode"].get()).split(" - ", 1)[0]),
            int(vars_for_group["hue"].get()),
            int(vars_for_group["sat"].get()),
            int(vars_for_group["val"].get()),
            int(vars_for_group["inner_param"].get()),
        ]

    def _all_groups_payload(self) -> list[int]:
        payload: list[int] = []
        for group_index in range(REG.GROUP_COUNT):
            payload.extend(self._group_payload(group_index))
        return payload

    def apply_group(self, group_index: int) -> None:
        try:
            client = self._require_client()
            addr = self.addr_var.get()
            client.write_multiple(
                addr,
                REG.GROUP_BASE + group_index * REG.GROUP_STRIDE,
                self._group_payload(group_index),
            )
            self.log_var.set(f"Group {group_index + 1} updated")
        except Exception as exc:
            messagebox.showerror("Apply Group Failed", str(exc))

    def apply_all(self) -> None:
        try:
            client = self._require_client()
            addr = self.addr_var.get()
            client.write_multiple(
                addr,
                REG.SCENE_MODE,
                [
                    int(self.scene_mode_var.get().split(" - ", 1)[0]),
                    self.scene_param_var.get(),
                ],
            )
            client.write_multiple(
                addr,
                REG.LED_GLOBAL_BRI,
                [
                    self.bri_var.get(),
                    self.gain_r_var.get(),
                    self.gain_g_var.get(),
                    self.gain_b_var.get(),
                ],
            )
            client.write_multiple(addr, REG.GROUP_BASE, self._all_groups_payload())
            self.log_var.set("All scene/global/group values applied")
        except Exception as exc:
            messagebox.showerror("Apply All Failed", str(exc))

    def copy_group1_to_all(self) -> None:
        template = self.group_vars[0]
        for group_index in range(1, REG.GROUP_COUNT):
            target = self.group_vars[group_index]
            target["inner_mode"].set(template["inner_mode"].get())
            target["hue"].set(template["hue"].get())
            target["sat"].set(template["sat"].get())
            target["val"].set(template["val"].get())
            target["inner_param"].set(template["inner_param"].get())
        self.log_var.set("Copied Group1 values into all groups")

    def set_all_groups_same(self) -> None:
        try:
            self.copy_group1_to_all()
            client = self._require_client()
            addr = self.addr_var.get()
            client.write_multiple(addr, REG.GROUP_BASE, self._all_groups_payload())
            self.log_var.set("Applied Group1 values to all groups")
        except Exception as exc:
            messagebox.showerror("Set All Groups Failed", str(exc))

    def clear_diag(self) -> None:
        try:
            self._require_client().clear_diag(self.addr_var.get())
            self.refresh_state()
            self.log_var.set("Diagnostics cleared")
        except Exception as exc:
            messagebox.showerror("Clear Failed", str(exc))


def main() -> None:
    root = tk.Tk()
    app = LumiaHostApp(root)
    root.minsize(860, 760)
    root.mainloop()
