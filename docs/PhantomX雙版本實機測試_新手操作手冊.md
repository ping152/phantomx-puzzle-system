# PhantomX 雙版本實機測試新手操作手冊

版本：1.0
更新日期：2026-09-16
適用系統：PhantomX Pincher、CM530、AX-12A、USB 相機、OpenCV、MoveIt、RViz

本手冊提供兩條完全分開的實機操作路線。第一次操作時，先依下表選擇環境，再只閱讀對應章節。不要把 Galactic 與 Humble 的指令混在同一次測試中。

| 你目前使用的環境 | 請閱讀 |
|---|---|
| 已存在的 Docker container 名稱是 `mytest`，ROS 位於 `/opt/ros/galactic` | 第 3 章 Galactic |
| 從 GitHub `phantomx-puzzle-system` 部署，ROS2 Humble | 第 4 章 Humble |

> 安全提醒：本系統會控制真實馬達。第一次實機測試不能直接從相機座標開始。必須依序完成相機檢查、PING、HOME、小幅 PT、MoveIt 安全位置，完成校正後才按 `R`。

## 1. 除了 container 還要開啟什麼

不論使用哪一個版本，完整流程都需要下列元件：

| 順序 | 元件 | 用途 | 是否會讓手臂動作 |
|---|---|---|---|
| 1 | CM530 USB serial 與馬達電源 | 將 ROS 命令送給 AX-12A | 電源打開本身不應移動 |
| 2 | MoveIt、fake controller、RViz | 計算 IK、規劃軌跡、顯示預期姿態 | fake controller 不控制實體馬達 |
| 3 | OpenCV pick-and-place service | 提供 `current_position` 與 `target_position` | 不會直接控制馬達 |
| 4 | `ros_main_controller` | 連接相機、MoveIt 與 CM530 | 啟動 HOME 或按 `R` 會驅動手臂 |
| 5 | 狀態檢查終端機 | 查看 service、action、controller | 不會控制馬達 |

資料流程如下：

```text
USB 相機
  -> OpenCV /camera/get_object_point
  -> ROS 主控 REP103 座標轉換
  -> MoveIt IK 與多點軌跡
  -> RViz 顯示預期軌跡
  -> radians 轉 AX position
  -> CM530 BEGIN / PT / END
  -> PhantomX AX-12A 馬達
```

RViz 的 `fake.launch.py` 仍然要開。它提供 MoveIt、fake ros2_control 與軌跡 action，讓主控可以計算路徑並顯示預期動作。真正的手臂則由同一組軌跡轉成 AX position 後，透過 CM530 控制。

## 2. 共通安全準備

### 2.1 開機前檢查

在接上馬達電源前逐項確認：

- 手臂四周沒有人、線材、工具或容易撞到的物品。
- 手臂固定牢靠，底座不會滑動。
- 操作者能立即切斷 AX 馬達與 CM530 電源。
- 吸盤尚未校正時，不把末端執行器放在桌面附近。
- 關閉 RoboPlus Terminal、手動 serial 程式及其他會占用 COM4 的工具。
- 同一時間只有一個 `ros_main_controller`。
- Windows 與 Jetson 不可同時控制同一支手臂。

> `STOP` 只會要求 CM530 保持最後目標位置，不會關閉 torque，也不是硬體急停。發生碰撞或失控時，直接切斷馬達電源。

### 2.2 第一次驗收順序

不要跳過或改變以下順序：

1. 確認相機畫面正常，OpenCV service 能回傳座標。
2. 測試 `PING -> PONG`。
3. 清空工作區後測試 `HOME -> OK,HOME`。
4. 測試第一軸 `512 -> 520 -> 512` 的小幅移動。
5. 在 RViz 測試 MoveIt 安全位置。
6. 校正相機比例、相機方向、桌面高度、AX center 與 sign。
7. 確認 OpenCV 座標落在手臂安全工作範圍後，才按 `R`。

### 2.3 使用手動工具完成小幅測試

第一次接上 CM530 時，先不要啟動 ROS 主控。使用 repository 內的手動工具驗證 serial 與馬達方向。

Windows 必須在 CM530 尚未 attach 到 WSL2、COM4 仍由 Windows 使用時執行：

```powershell
python .\components\cm530\manual_position_terminal.py --port COM4
```

Jetson 必須在所有 ROS container 都停止時執行：

```bash
python3 components/cm530/manual_position_terminal.py \
  --port /dev/phantomx-cm530
```

依序輸入：

```text
PING
HOME
demo
STOP
```

`demo` 使用正式 BEGIN/PT/END 協議，讓第一軸執行 `512 -> 520 -> 512`。測試過程仍須保持斷電方式可用。每一步都應收到 `PONG` 或對應 `OK,...`；出現 `ERR`、timeout 或方向錯誤時立即停止。

完成後輸入 `quit` 或按 `Ctrl+C` 關閉工具。確認程式已釋放 serial，才能把 CM530 attach 到 WSL2 或啟動 ROS 主控。同一時間不可讓手動工具與 ROS 主控開啟同一個 serial port。

### 2.4 按 R 目前會做什麼

按一次 `R` 會：

1. 取得 OpenCV `current_position` 和 `target_position`。
2. 把 current 的 camera XY 轉成手臂 base XY。
3. 規劃到物品上方的接近點。
4. 規劃垂直下降到取物高度。
5. 將同一份多點軌跡送給 RViz 與 CM530。

目前不會控制吸盤、不會拿起拼圖、不會前往 `target_position`、不會放下拼圖，也不會自動返回 HOME。

## 3. Galactic mytest 實機流程

本章只適用：

```text
Container: mytest
ROS: /opt/ros/galactic
Workspace: /root/ws
```

### 3.1 確認 Docker 與 mytest

執行位置：Windows PowerShell。

```powershell
docker version
docker ps -a --filter name=mytest
docker start mytest
docker exec mytest bash -lc "test -f /opt/ros/galactic/setup.bash && echo Galactic_OK"
```

預期看到：

```text
Galactic_OK
```

若 `docker version` 只有 Client、沒有 Server，或顯示找不到 `docker_engine`，表示 Docker Desktop 背景引擎沒有運行。先修復或啟動 Docker Desktop，不要繼續。

### 3.2 將 CM530 提供給 WSL2

執行位置：系統管理員 Windows PowerShell。

先關閉所有使用 COM4 的程式，再列出 USB 裝置：

```powershell
usbipd list
```

找到 CM530 對應的 `<BUSID>`。第一次使用時：

```powershell
usbipd bind --busid <BUSID>
```

每次重新插拔或重新開機後：

```powershell
usbipd attach --wsl --busid <BUSID>
```

執行位置：WSL2 terminal。

```bash
lsusb
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

記下實際裝置名稱，例如 `/dev/ttyUSB0` 或 `/dev/ttyACM0`。CM530 attach 到 WSL2 後，Windows 的 COM4 不能同時被其他程式使用。

### 3.3 確認 mytest 看得到 serial

執行位置：Windows PowerShell。

```powershell
docker inspect --format '{{json .HostConfig.Devices}}' mytest
docker exec mytest bash -lc "ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"
docker exec mytest python3 -c "import serial; print(serial.__version__)"
```

只有在 container 內能看到 serial device 時才能繼續。

若 `HostConfig.Devices` 是空陣列，而且 container 內沒有 `/dev/ttyUSB*` 或 `/dev/ttyACM*`：

- 單純 `docker restart mytest` 不會加入裝置。
- 不要刪除 `mytest`，先執行 `docker inspect mytest` 保存 image、mount、network 與工作目錄設定。
- 建立另一個硬體測試 container，例如 `mytest-hw`，複製原設定並加入 `--device=<WSL裝置>:<容器裝置>`。
- 建立後重新同步 `/root/ws/src/ros2_main_control` 與 `opencv_ros2_bridge_interfaces`，再執行 colcon build。

由於每台電腦的 image 與 mount 路徑不同，不要直接複製別台電腦的 `docker run` 指令覆蓋現有 container。

### 3.4 確認 Galactic workspace 已建置

執行位置：Windows PowerShell。

```powershell
docker exec -it mytest bash
```

執行位置：mytest 容器內。

```bash
source /opt/ros/galactic/setup.bash
cd /root/ws
colcon build --merge-install \
  --packages-select opencv_ros2_bridge_interfaces ros2_main_control
source /root/ws/install/setup.bash
ros2 pkg executables ros2_main_control
```

預期可以看到：

```text
ros2_main_control ros_main_controller
```

每一個新開的 mytest terminal 都必須執行：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
```

### 3.5 Terminal 1 啟動 MoveIt 與 RViz

執行位置：Windows PowerShell。

```powershell
docker exec -it mytest bash
```

執行位置：mytest Terminal 1。

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 launch phantomx_pincher fake.launch.py log_level:=error
```

保持 Terminal 1 開啟。預期 RViz 出現 PhantomX 模型。`fake.launch.py` 不會直接驅動實體馬達，它提供 MoveIt、fake controller 與 RViz 顯示。

### 3.6 Terminal 2 啟動 OpenCV

執行位置：可正常使用相機與 OpenCV ROS2 的 WSL2 terminal，不是在 mytest 內。

```bash
cd "/mnt/d/畢業專題/OpenCV/OpenCV_ROS2_Bridge_test.01-main"
./start_pp.sh
```

`start_pp.sh` 必須使用 `processing_mode:=pick-and-place`，並 source 已建置 `opencv_ros2_bridge_interfaces` 的 ROS workspace。保持 Terminal 2 開啟，確認相機畫面能辨識物品。

### 3.7 Terminal 4 先做 ROS 狀態檢查

在主控之前先開一個檢查終端機。

執行位置：Windows PowerShell。

```powershell
docker exec -it mytest bash
```

執行位置：mytest Terminal 4。

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash

ros2 service list -t | grep -E 'compute_ik|plan_kinematic_path|compute_cartesian_path|get_object_point'
ros2 action list -t | grep /joint_trajectory_controller/follow_joint_trajectory
ros2 control list_controllers
```

必須看到：

```text
/compute_ik [moveit_msgs/srv/GetPositionIK]
/plan_kinematic_path [moveit_msgs/srv/GetMotionPlan]
/compute_cartesian_path [moveit_msgs/srv/GetCartesianPath]
/camera/get_object_point [opencv_ros2_bridge_interfaces/srv/GetObjectPoint]
/joint_trajectory_controller/follow_joint_trajectory [control_msgs/action/FollowJointTrajectory]
joint_trajectory_controller ... active
```

少任何一項都先停止，不要啟動主控。若只有 camera service 看不到，檢查 OpenCV 與 mytest 的 `ROS_DOMAIN_ID` 是否相同。

### 3.8 Terminal 3 啟動 Galactic 主控

> 危險動作前警告：Galactic 主控啟動後會自動傳送 `PING` 和 `HOME`。執行下一個 `ros2 run` 前，必須清空工作區並準備切斷馬達電源。不要等按 R 才做安全準備。

執行位置：Windows PowerShell。

```powershell
docker exec -it mytest bash
```

執行位置：mytest Terminal 3。

以下範例假設 CM530 是 `/dev/ttyUSB0`：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 run ros2_main_control ros_main_controller --ros-args \
  -p serial_port:=/dev/ttyUSB0
```

若實際裝置是 `/dev/ttyACM0`，必須改成：

```bash
-p serial_port:=/dev/ttyACM0
```

正常啟動時應看到類似訊息：

```text
CM530 serial opened: /dev/ttyUSB0 @ 57600
TX -> PING
RX <- PONG
Sending startup HOME trajectory to RViz fake controller.
TX -> HOME
RX <- OK,HOME
RViz startup HOME trajectory finished.
Startup HOME sequence finished.
```

若出現 `Failed to open CM530 serial port`、PING timeout 或 HOME 失敗，不能按 `R`。

### 3.9 按 R 前最後檢查

在按 `R` 前逐項確認：

- Terminal 1 的 MoveIt/RViz 沒有停止。
- Terminal 2 的相機畫面與辨識結果合理。
- Terminal 3 已顯示 `Startup HOME sequence finished.`。
- Terminal 4 可以看到全部 services 與 action。
- `current_position` 落在已校正的安全工作範圍。
- `target_z_offset_m`、`pickup_z_m` 與桌面高度已用實機校正。
- AX center/sign 已確認，手臂各軸方向正確。
- 現場人員已離開手臂工作區。

確認後，在 Terminal 3 直接按鍵盤 `R`，不需要按 Enter。

## 4. Humble GitHub 部署版

Humble 版不使用 `mytest`。它使用 `phantomx-puzzle-system` 的 Docker Compose 與安全啟動腳本。

### 4.1 取得固定版本與 release.env

Windows PowerShell 或 Jetson terminal：

```bash
git clone --recurse-submodules --branch v0.1.0-rc2 https://github.com/ping152/phantomx-puzzle-system.git
cd phantomx-puzzle-system
```

Windows PowerShell 下載固定 digest：

```powershell
Invoke-WebRequest `
  https://github.com/ping152/phantomx-puzzle-system/releases/download/v0.1.0-rc2/release.env `
  -OutFile .env
```

Jetson 下載固定 digest：

```bash
curl -fL \
  https://github.com/ping152/phantomx-puzzle-system/releases/download/v0.1.0-rc2/release.env \
  -o .env
```

`.env` 應包含兩個 `@sha256:` 映像與：

```text
RELEASE_MODE=1
```

### 4.2 Humble Windows 模擬測試

執行位置：系統管理員 Windows PowerShell。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup-windows.ps1
.\scripts\test-windows-sim.ps1
```

Windows 實機相機 sender 需要 Windows Python 與 OpenCV。開始實機前先檢查：

```powershell
python --version
python -c "import cv2; print(cv2.__version__)"
```

若沒有 Python，可使用 `winget install --id Python.Python.3.10` 安裝；若只有 `cv2` 缺少，可執行 `python -m pip install opencv-python`。安裝後關閉並重新開啟 PowerShell，再重跑上面的檢查。

模擬測試只使用 fake controller 與 mock serial，不會驅動真實手臂。模擬失敗時不要進入實機模式。

### 4.3 Humble Windows 實機啟動

先以系統管理員 PowerShell 找到 CM530 的 BUSID：

```powershell
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

`bind` 通常只需第一次執行；`attach` 在重新插拔或重新開機後可能要重做。接著確認 WSL 內的 serial 名稱：

```powershell
wsl -e sh -lc "ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"
```

確認裝置後再執行：

```powershell
$env:HARDWARE_OWNER="windows"
$env:CM530_DEVICE="/dev/ttyUSB0"
$env:ROS_DOMAIN_ID="31"
.\scripts\start-windows-hardware.ps1 -CameraIndex 0
```

若 serial 是 `/dev/ttyACM0`，修改 `CM530_DEVICE`。腳本會檢查 Docker、usbipd、相機、serial 與重複主控。

看到以下提示時：

```text
Disconnect people/tools from the arm, make STOP reachable, then type HOME to authorize homing
```

再次清空工作區，確認斷電方式可用，然後輸入：

```text
HOME
```

輸入其他文字會中止，不會授權 HOME。主控 ready 後，才可以在互動終端機按 `R`。

### 4.4 Humble Jetson 模擬測試

執行位置：Jetson terminal。

```bash
chmod +x scripts/*.sh docker/*.sh
./scripts/setup-jetson.sh
./scripts/test-jetson-sim.sh
```

腳本必須確認：

```text
uname -m = aarch64
/etc/nv_tegra_release 存在
JetPack 可辨識
Docker 與 NVIDIA Container Toolkit 可用
```

未知 JetPack 或非 ARM64 時會停止，不會自動重刷 Jetson。

### 4.5 Humble Jetson 實機啟動

有本機螢幕與 RViz：

```bash
export HARDWARE_OWNER=jetson
export DISPLAY=:0
export ENABLE_RVIZ=true
export CM530_DEVICE=/dev/phantomx-cm530
export CAMERA_DEVICE=/dev/video0
./scripts/start-jetson-hardware.sh
```

Headless Jetson：

```bash
export HARDWARE_OWNER=jetson
export ENABLE_RVIZ=false
export VISION_SHOW_WINDOW=false
export CM530_DEVICE=/dev/phantomx-cm530
export CAMERA_DEVICE=/dev/video0
./scripts/start-jetson-hardware.sh
```

Jetson 腳本同樣會要求輸入 `HOME`。只有輸入完全相同的大寫 `HOME` 才會繼續。主控 ready 後，在互動終端機按 `R`。

## 5. 按 R 後應該看到什麼

成功取得 OpenCV 回覆時，主控會先顯示原始座標：

```text
OpenCV current_position: x=0.0303, y=0.0685, z=0.0000
OpenCV target_position: x=0.0600, y=-0.0200, z=0.0000
```

接著顯示 REP103 轉換後的手臂座標：

```text
Mapped base current_approach_pose: x=0.0685, y=-0.0303, z=0.0500, yaw=...
Mapped base current_pickup_pose: x=0.0685, y=-0.0303, z=0.0200, yaw=...
Mapped base target_not_executed_pose: x=-0.0200, y=-0.0600, z=0.0500, yaw=...
```

規劃成功後顯示：

```text
Planned <N> points, duration=<毫秒> ms;
final radians=[...], AX=[...]
```

這些訊息分別代表：

| 訊息 | 可以確認什麼 |
|---|---|
| `OpenCV current_position` | OpenCV 實際送給 ROS 的物品座標 |
| `OpenCV target_position` | OpenCV 找到的放置座標，目前只顯示 |
| `current_approach_pose` | MoveIt 使用的物品上方位置 |
| `current_pickup_pose` | 垂直下降的命令終點 |
| `Planned N points` | MoveIt 已產生完整多點軌跡 |
| `final radians` | 最後一點的四軸關節角度 |
| `AX` | 最後一點轉換後的 AX-12A position |

CM530 不會收到 XYZ。主控會把每一個 MoveIt 軌跡點轉成：

```text
BEGIN,<traj_id>,4,<point_count>
PT,<seq>,<dt_ms>,<AX1>,<AX2>,<AX3>,<AX4>
...
END,<traj_id>
```

每一筆 PT 都要收到對應 ACK 才會繼續。ACK 只能證明 CM530 接受指令，因為目前沒有 AX-12A present position 回授，不能證明馬達已準確到位。

## 6. 正常停止與緊急處理

### 6.1 Galactic 正常停止

依序操作：

1. 在主控 Terminal 3 按 `Ctrl+C`，等待 STOP 與 serial 清理。
2. 在 OpenCV Terminal 2 按 `Ctrl+C`，釋放相機。
3. 在 MoveIt Terminal 1 按 `Ctrl+C`。
4. Windows PowerShell 執行：

```powershell
docker stop mytest
```

5. 不再使用 CM530 時：

```powershell
usbipd detach --busid <BUSID>
```

### 6.2 Humble Windows 正常停止

```powershell
.\scripts\stop-windows.ps1
```

### 6.3 Humble Jetson 正常停止

```bash
./scripts/stop-jetson.sh
```

停止腳本會先停止主控並嘗試 STOP，再關閉 OpenCV、MoveIt 與 container。仍然不能把軟體 STOP 當成硬體急停。

### 6.4 危險狀況

如果手臂碰撞、方向明顯錯誤、持續移動或有人進入工作區：

1. 立即切斷 AX 馬達與 CM530 電源。
2. 不要先等待 ROS timeout、RViz 或 STOP。
3. 排除原因前不要再次 HOME 或按 `R`。
4. 重新檢查 AX sign、center、相機方向、桌面高度與座標範圍。

## 7. 常見問題

| 現象 | 原因 | 處理方式 |
|---|---|---|
| `docker_engine` 找不到 | Docker Desktop daemon 沒運行 | 啟動或修復 Docker Desktop |
| container 看不到 serial | 建立 container 時沒有 device mapping | 保留原 container，檢查設定後建立硬體測試 container |
| `Failed to open CM530 serial port` | 路徑錯誤、未 attach、權限不足或被占用 | 檢查 usbipd、裝置名稱，關閉 RoboPlus 與手動工具 |
| `Camera service not available` | OpenCV 未啟動、interface 未建置或 ROS domain 不同 | 啟動 `start_pp.sh`，檢查 package 與 `ROS_DOMAIN_ID` |
| 找不到 `/compute_ik` | MoveIt 尚未完成啟動 | 保持 fake.launch.py 運行並重新檢查 services |
| RViz 不動但手臂收到命令 | trajectory action 不存在或 RViz 同步失敗 | 檢查 action/controller；實體路徑採最佳努力，不以 RViz 判斷到位 |
| HOME 失敗 | PING、serial、ACK 或 CM530/AX bus 問題 | 不按 R，停止主控並從 PING 重新測試 |
| `R` 被鎖定 | CM530 中途失敗後位置未知 | 排除故障，重新啟動主控並成功 HOME |
| Cartesian fraction 小於 1 | 垂降路徑不完整 | 不會送 serial；調整安全座標、姿態或高度後重試 |
| AX 超出 0..1023 | 校正值或 IK 結果超出 AX 範圍 | 整段軌跡會拒絕；檢查 center、sign、scale 與工作點 |

## 8. 操作人員快速檢查表

### 8.1 啟動前

- [ ] 已選定 Galactic 或 Humble，不混用指令。
- [ ] 工作區清空，實體斷電方式可立即操作。
- [ ] 只有一台電腦、一道主控可以控制 CM530。
- [ ] RoboPlus 與手動 serial 工具已關閉。
- [ ] CM530 serial 路徑已確認。
- [ ] 相機畫面正常。

### 8.2 主控啟動前

- [ ] MoveIt services 全部存在。
- [ ] trajectory action 與 controller 存在。
- [ ] `/camera/get_object_point` 存在。
- [ ] Galactic 已理解主控啟動會立即自動 HOME。
- [ ] Humble 已準備在提示時輸入 `HOME`。

### 8.3 按 R 前

- [ ] PING 與 HOME 成功。
- [ ] 已完成 512/520/512 小幅測試。
- [ ] 相機座標、REP103 方向、桌面高度與 AX sign 已校正。
- [ ] current 座標在安全工作範圍。
- [ ] 所有人已離開手臂工作區。

### 8.4 停止後

- [ ] 主控先停止並完成 serial 清理。
- [ ] OpenCV 已釋放相機。
- [ ] MoveIt/RViz 已停止。
- [ ] container 已停止。
- [ ] 不再使用時已 detach USB 並關閉馬達電源。

## 9. 相關文件

- `docs/ROS2主控節點_完整操作手冊.md`：Galactic 主控、軌跡、協議與測試技術細節。
- `docs/DEPLOYMENT_WINDOWS_JETSON.md`：Humble Windows 與 Jetson 部署細節。
- `components/controller/README.md`：ROS 主控參數與測試。
- `components/cm530/ROS_CM530_INTERFACE_SPEC.txt`：CM530 正式 serial 協議。

本手冊提供操作順序，不代表實機校正已完成。任何平台第一次接上真實手臂時，都必須從 PING、HOME 與小幅 PT 開始驗收。
