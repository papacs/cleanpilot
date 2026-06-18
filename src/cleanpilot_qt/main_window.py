import os
from pathlib import Path

from PySide6.QtCore import QObject, QThread, Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QButtonGroup,
    QCheckBox,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QProgressBar,
    QRadioButton,
    QSpinBox,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .engine import (
    build_powershell_command,
    parse_dry_run_line,
    recommendation_for_candidates,
    run_command,
)
from .models import CleanupCandidate


class EngineWorker(QObject):
    line_received = Signal(str)
    candidate_found = Signal(object)
    finished = Signal(int)

    def __init__(self, command: list[str], cwd: Path):
        super().__init__()
        self.command = command
        self.cwd = cwd

    def run(self):
        candidates: list[CleanupCandidate] = []

        def handle_line(line: str):
            self.line_received.emit(line)
            candidate = parse_dry_run_line(line)
            if candidate is not None:
                candidates.append(candidate)
                self.candidate_found.emit(candidate)

        exit_code = run_command(self.command, self.cwd, handle_line)
        self.finished.emit(exit_code)


class CleanPilotWindow(QMainWindow):
    def __init__(self, repo_root: Path):
        super().__init__()
        self.repo_root = repo_root
        self.script_path = repo_root / "SafeDiskCleanup.ps1"
        self.log_dir = Path(os.environ.get("ProgramData", "C:\\ProgramData")) / "SafeDiskCleanup" / "Logs"
        self.candidates: list[CleanupCandidate] = []
        self.log_lines: list[str] = []
        self.worker_thread: QThread | None = None
        self.worker: EngineWorker | None = None
        self.current_operation = "idle"

        self.setWindowTitle("CleanPilot")
        self._build_ui()
        self._set_idle_state()

    def _build_ui(self):
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(12)

        layout.addLayout(self._build_header())
        layout.addWidget(self._build_recommendation_panel())
        layout.addWidget(self._build_content(), stretch=1)
        layout.addWidget(self._build_footer())

        self.setCentralWidget(root)

    def _build_header(self):
        header = QGridLayout()
        header.setHorizontalSpacing(12)
        header.setVerticalSpacing(8)

        title = QLabel("CleanPilot")
        title.setObjectName("appTitle")
        subtitle = QLabel("安全扫描、推荐清理、实时日志的 Windows 磁盘清理助手")
        subtitle.setObjectName("appSubtitle")

        self.admin_label = QLabel("权限：检测中")
        self.admin_label.setObjectName("statusBadge")

        self.scan_button = QPushButton("扫描")
        self.scan_button.setObjectName("primaryButton")
        self.scan_button.clicked.connect(self.start_scan)

        self.clean_button = QPushButton("清理选中项")
        self.clean_button.clicked.connect(self.confirm_clean)

        self.open_log_button = QPushButton("打开日志")
        self.open_log_button.clicked.connect(self.open_log_dir)

        self.open_script_button = QPushButton("打开脚本目录")
        self.open_script_button.clicked.connect(lambda: os.startfile(str(self.repo_root)))

        self.safe_mode = QRadioButton("安全模式")
        self.safe_mode.setChecked(True)
        self.deep_scan = QRadioButton("深度扫描")
        self.mode_group = QButtonGroup(self)
        self.mode_group.addButton(self.safe_mode)
        self.mode_group.addButton(self.deep_scan)

        self.min_age_days = QSpinBox()
        self.min_age_days.setRange(0, 3650)
        self.min_age_days.setValue(7)
        self.min_age_days.setSuffix(" 天")

        controls = QHBoxLayout()
        controls.addWidget(self.scan_button)
        controls.addWidget(self.clean_button)
        controls.addWidget(self.open_log_button)
        controls.addWidget(self.open_script_button)
        controls.addSpacing(12)
        controls.addWidget(self.safe_mode)
        controls.addWidget(self.deep_scan)
        controls.addSpacing(12)
        controls.addWidget(QLabel("最小文件年龄"))
        controls.addWidget(self.min_age_days)
        controls.addStretch()

        header.addWidget(title, 0, 0)
        header.addWidget(self.admin_label, 0, 1)
        header.addWidget(subtitle, 1, 0, 1, 2)
        header.addLayout(controls, 2, 0, 1, 2)
        return header

    def _build_recommendation_panel(self):
        self.recommendation_label = QLabel("建议先点击“扫描”，查看可安全清理的项目。")
        self.recommendation_label.setObjectName("recommendationPanel")
        self.recommendation_label.setWordWrap(True)
        return self.recommendation_label

    def _build_content(self):
        splitter = QSplitter()

        left = QFrame()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.addWidget(QLabel("清理候选项"))

        self.table = QTableWidget(0, 6)
        self.table.setHorizontalHeaderLabels(["选择", "类别", "风险", "预估大小", "文件数", "路径"])
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setHorizontalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.table.setTextElideMode(Qt.ElideNone)
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setStretchLastSection(False)
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(5, QHeaderView.Interactive)
        self.table.setColumnWidth(5, 520)
        self.table.itemSelectionChanged.connect(self.update_detail_panel)
        left_layout.addWidget(self.table)

        right = QFrame()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.addWidget(QLabel("详情"))
        self.detail_text = QTextEdit()
        self.detail_text.setReadOnly(True)
        self.detail_text.setMinimumWidth(320)
        self.detail_text.setText("选择一个清理项查看路径、风险和推荐说明。")
        right_layout.addWidget(self.detail_text, stretch=1)
        right_layout.addWidget(QLabel("实时日志"))
        self.log_view = QTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMinimumHeight(220)
        right_layout.addWidget(self.log_view, stretch=2)

        splitter.addWidget(left)
        splitter.addWidget(right)
        splitter.setSizes([760, 420])
        return splitter

    def _build_footer(self):
        footer = QVBoxLayout()
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        self.operation_label = QLabel("就绪")
        footer.addWidget(self.progress_bar)
        footer.addWidget(self.operation_label)
        box = QWidget()
        box.setLayout(footer)
        return box

    def _set_idle_state(self):
        is_admin = self._is_admin()
        self.admin_label.setText("权限：管理员" if is_admin else "权限：普通权限")
        self.clean_button.setEnabled(False)
        self.progress_bar.setValue(0)

    def _is_admin(self) -> bool:
        try:
            import ctypes

            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            return False

    def start_scan(self):
        self.current_operation = "scan"
        self.candidates.clear()
        self.log_lines.clear()
        self.table.setRowCount(0)
        self.log_view.clear()
        self.detail_text.setText("扫描中...")
        self.recommendation_label.setText("正在扫描，请稍候。")
        self.progress_bar.setRange(0, 0)
        self.operation_label.setText("正在扫描清理候选项")
        self.clean_button.setEnabled(False)

        command = build_powershell_command(
            script_path=self.script_path,
            dry_run=True,
            aggressive=self.deep_scan.isChecked(),
            min_age_days=self.min_age_days.value(),
        )
        self._start_worker(command)

    def confirm_clean(self):
        selected = [item for item in self.candidates if item.selected]
        if not selected:
            QMessageBox.information(self, "没有选中项", "请先选择至少一个清理项。")
            return

        answer = QMessageBox.question(
            self,
            "确认清理",
            "将调用 SafeDiskCleanup.ps1 执行清理。当前版本会按脚本允许清单执行清理，请确认已查看日志和推荐信息。",
        )
        if answer != QMessageBox.Yes:
            return

        self.current_operation = "clean"
        self.log_view.append("开始清理：调用 SafeDiskCleanup.ps1")
        self.progress_bar.setRange(0, 0)
        self.operation_label.setText("正在清理")
        command = build_powershell_command(
            script_path=self.script_path,
            dry_run=False,
            aggressive=self.deep_scan.isChecked(),
            min_age_days=self.min_age_days.value(),
        )
        self._start_worker(command)

    def _start_worker(self, command: list[str]):
        self.scan_button.setEnabled(False)
        self.clean_button.setEnabled(False)
        self.worker_thread = QThread(self)
        self.worker = EngineWorker(command, self.repo_root)
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.line_received.connect(self.append_log_line)
        self.worker.candidate_found.connect(self.add_candidate)
        self.worker.finished.connect(self.finish_run)
        self.worker.finished.connect(self.worker_thread.quit)
        self.worker.finished.connect(self.worker.deleteLater)
        self.worker_thread.finished.connect(self.worker_thread.deleteLater)
        self.worker_thread.start()

    def append_log_line(self, line: str):
        self.log_lines.append(line)
        self.log_view.append(line)
        if "Log path:" in line:
            _, value = line.split("Log path:", 1)
            log_path = Path(value.strip())
            if log_path.parent.exists():
                self.log_dir = log_path.parent

    def add_candidate(self, candidate: CleanupCandidate):
        self.candidates.append(candidate)
        row = self.table.rowCount()
        self.table.insertRow(row)

        self.table.setCellWidget(row, 0, self._make_checkbox_cell(candidate))
        self._set_table_item(row, 1, candidate.name)
        self._set_table_item(row, 2, candidate.risk)
        self._set_table_item(row, 3, candidate.estimated_size)
        self._set_table_item(row, 4, str(candidate.file_count))
        path_item = QTableWidgetItem(candidate.path)
        path_item.setToolTip(candidate.path)
        self.table.setItem(row, 5, path_item)
        self.table.resizeColumnToContents(5)

    def _make_checkbox_cell(self, candidate: CleanupCandidate) -> QWidget:
        wrapper = QWidget()
        layout = QHBoxLayout(wrapper)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setAlignment(Qt.AlignCenter)
        checkbox = QCheckBox()
        checkbox.setChecked(candidate.selected)
        checkbox.stateChanged.connect(lambda state, item=candidate: setattr(item, "selected", state == 2))
        layout.addWidget(checkbox)
        return wrapper

    def _set_table_item(self, row: int, column: int, text: str):
        item = QTableWidgetItem(text)
        self.table.setItem(row, column, item)

    def finish_run(self, exit_code: int):
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100 if exit_code == 0 else 0)
        self.scan_button.setEnabled(True)
        self.operation_label.setText("完成" if exit_code == 0 else f"失败，退出码 {exit_code}")
        if self.current_operation == "clean" and exit_code == 0:
            self._clear_candidates_after_cleanup()
            self.recommendation_label.setText("清理完成。候选项已清空，请重新扫描查看最新结果。")
        else:
            self.clean_button.setEnabled(bool(self.candidates))
            self.recommendation_label.setText(
                recommendation_for_candidates(self.candidates, self.log_lines, self._is_admin())
            )
        self.current_operation = "idle"
        self.worker = None
        self.worker_thread = None

    def _clear_candidates_after_cleanup(self):
        self.candidates.clear()
        self.table.clearSelection()
        self.table.setRowCount(0)
        self.clean_button.setEnabled(False)
        self.detail_text.setText("清理完成。候选项已清空，请重新扫描查看最新结果。")

    def update_detail_panel(self):
        indexes = self.table.selectionModel().selectedRows()
        if not indexes:
            return
        row = indexes[0].row()
        if row >= len(self.candidates):
            return
        item = self.candidates[row]
        self.detail_text.setText(
            "\n".join(
                [
                    f"类别：{item.name}",
                    f"风险：{item.risk}",
                    f"预估大小：{item.estimated_size}",
                    f"文件数：{item.file_count}",
                    f"路径：{item.path}",
                    f"推荐：{item.recommendation}",
                ]
            )
        )

    def open_log_dir(self):
        self.log_dir.mkdir(parents=True, exist_ok=True)
        os.startfile(str(self.log_dir))
