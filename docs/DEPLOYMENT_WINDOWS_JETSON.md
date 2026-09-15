# Windows 與 Jetson 完整部署手冊

## 1. 系統邊界

正式基底為 ROS 2 Humble。Windows 在 Docker Desktop 的 Linux VM 內執行 `linux/amd64`；Jetson AGX Orin 在 Jetson Ubuntu 上原生執行 `linux/arm64`。不使用 ARM 模擬執行 Jetson 正式系統，也不把 Ubuntu x86_64 當成第三個目標。

兩個映像：

- `phantomx-puzzle-motion`: PhantomX、MoveIt、fake controller、主控與 pyserial。
- `phantomx-puzzle-vision`: OpenCV、相機 publisher 與 `GetObjectPoint` service。

## 2. 共通安全規則

1. 實機前拔除桌面上無關物品，確認急停與 CM530 電源可立即切斷。
2. 同一時間只有一台電腦可控制手臂。
3. Windows 使用 `HARDWARE_OWNER=windows`；Jetson 使用 `HARDWARE_OWNER=jetson`。
4. 安裝與模擬腳本永遠不啟動硬體 profile。
5. 實機腳本會檢查 serial、camera、重複 ROS 節點，再要求輸入 `HOME`。
6. 結束時按 `Ctrl+C` 或執行 stop 腳本；腳本先送 SIGINT，讓主控嘗試 `STOP`，再關閉容器。
7. `STOP` 是軟體層保護，不能取代實體斷電或急停。

## 3. Windows 安裝

以系統管理員 PowerShell 執行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup-windows.ps1
```

腳本檢查或安裝 Git、GitHub CLI、Docker Desktop 與 usbipd-win，並確認 WSL2。若 WSL2 尚未完成，依訊息重新開機後再執行。

Docker Desktop 必須使用 Linux containers，並啟用 WSL2 integration。RViz 需要 WSLg 或可用的 X11 顯示；無 GUI 驗證可先設定 `$env:ENABLE_RVIZ="false"`。

### Windows USB

USB 相機由 Windows 原生 sender 開啟，經 TCP `5001` 傳進 vision 容器。CM530 用 usbipd 掛入 WSL2：

```powershell
usbipd list
usbipd bind --busid <CM530-BUSID>
usbipd attach --wsl --busid <CM530-BUSID>
wsl -e sh -lc "ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"
```

相機 sender 與 CM530 不應使用同一個 USB 裝置。重新插拔後裝置名稱可能改變，啟動前再次確認。

### Windows 模擬

```powershell
.\scripts\test-windows-sim.ps1
```

腳本建置 amd64 映像、執行 controller 單元測試、啟動 fake MoveIt，並跑八組多點軌跡探針。它只使用 mock serial。

### Windows 實機

```powershell
$env:HARDWARE_OWNER="windows"
$env:CM530_DEVICE="/dev/ttyUSB0"
$env:ROS_DOMAIN_ID="31"
.\scripts\start-windows-hardware.ps1 -CameraIndex 0
```

看到主控 ready 後按 `R`。一次 `R` 執行 current 物品的接近與垂降；目前不吸取、不搬運到 target。停止：

```powershell
.\scripts\stop-windows.ps1
```

## 4. Jetson 安裝

```bash
chmod +x scripts/*.sh docker/*.sh
./scripts/setup-jetson.sh
```

腳本檢查 `uname -m`、`/etc/os-release`、`/etc/nv_tegra_release`、JetPack、Docker 與 NVIDIA Container Toolkit。架構不是 `aarch64` 或 JetPack 無法辨識時會停止，且不會自動重刷 BSP。

重新登入後確認：

```bash
docker info
groups
ls -l /dev/video0 /dev/ttyUSB0
```

建立 CM530 固定別名時，先找 USB ID：

```bash
udevadm info --attribute-walk --name=/dev/ttyUSB0
export CM530_USB_VENDOR_ID=xxxx
export CM530_USB_PRODUCT_ID=yyyy
./scripts/setup-jetson.sh
```

### Jetson 模擬

```bash
./scripts/test-jetson-sim.sh
```

此流程必須在 Jetson 原生 ARM64 執行，並重跑單元測試與 8/8 MoveIt 探針。

### Jetson 實機

有本機螢幕：

```bash
export HARDWARE_OWNER=jetson
export DISPLAY=:0
export ENABLE_RVIZ=true
export CM530_DEVICE=/dev/phantomx-cm530
export CAMERA_DEVICE=/dev/video0
./scripts/start-jetson-hardware.sh
```

Headless：

```bash
export HARDWARE_OWNER=jetson
export ENABLE_RVIZ=false
export VISION_SHOW_WINDOW=false
./scripts/start-jetson-hardware.sh
```

停止：

```bash
./scripts/stop-jetson.sh
```

## 5. Windows 遠端 RViz

Jetson headless 與 Windows RViz 必須明確使用同一 domain；一般獨立測試時 Windows 預設 `31`、Jetson 預設 `32`，避免兩個主控互相看見。

遠端 RViz 模式：

1. Jetson 啟動 discovery server：`docker compose --profile discovery up -d discovery-server`。
2. Jetson 與 Windows 都設定相同 `ROS_DOMAIN_ID=32`。
3. 兩端設定 `ROS_DISCOVERY_SERVER=<JETSON_IP>:11811`。
4. Jetson 防火牆只對可信任 LAN 開放 discovery port `11811` 與必要 DDS 流量。
5. Windows 只執行 RViz，不啟動另一個 `ros_main_controller`。

網路隔離、VPN 或防火牆規則可能阻擋 DDS。先以 `ros2 node list`、`ros2 topic echo /joint_states --once` 驗證，再開 RViz。

## 6. 正式映像與 digest

開發建置可使用 RC tag。正式部署先取得 workflow 產生的 `release.env`，內容必須類似：

```dotenv
MOTION_IMAGE=ghcr.io/ping152/phantomx-puzzle-motion@sha256:<64 hex>
VISION_IMAGE=ghcr.io/ping152/phantomx-puzzle-vision@sha256:<64 hex>
RELEASE_MODE=1
```

`RELEASE_MODE=1` 時，實機腳本拒絕 tag 與 `latest`，只接受 SHA-256 digest。

## 7. 實機驗收順序

1. 確認相機畫面與 `/camera/get_object_point`。
2. 只測 `PING -> PONG`。
3. 清空工作區後測 `HOME -> OK,HOME`。
4. 用手動工具送第一軸 512/520/512 的小幅 PT。
5. 用 MoveIt 安全座標測試，不接近桌面。
6. 校正 `target_z_offset_m`、`pickup_z_m` 後，才測按 `R` 的接近與垂降。

每台平台都要重新校正相機外參、桌面高度、AX center/sign 和安全範圍。模擬通過不表示馬達真實位置已被量測；CM530 目前沒有把 AX present position 回傳給 ROS。

## 8. 故障排除

- 找不到 `/compute_ik`：檢查 moveit container health、ROS domain 與 workspace overlay。
- 找不到 action：確認 `/joint_trajectory_controller/follow_joint_trajectory` 已出現。
- Windows 無相機：先執行 `python components/vision/windows_camera_ros_sender.py --scan`。
- CM530 timeout：停止控制器，確認 USB attach、baud 57600、LF 結尾與 serial 是否被其他程式占用。
- RViz 沒同步但手臂有動：RViz 是最佳努力路徑；檢查 action server 與主控 warning。
- Cartesian fraction 小於 1.0 或 AX 超界：主控會在 serial 送出前拒絕整段軌跡，先調整工作點與校正值。

