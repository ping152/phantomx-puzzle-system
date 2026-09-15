# ROS2 主控節點完整操作手冊

版本：1.3  
整理日期：2026-09-04  
適用專案：OpenCV 桌面拼圖辨識、PhantomX Pincher、CM530、AX-12A、ROS2 Galactic

本手冊說明按 R 取得座標後，規劃 end-effector link 至 base 座標 z=0.05 m，再垂降至 z=0.02 m 的操作及故障復原流程。兩段軌跡必須完整預先驗證，才能送往 RViz 與 CM530。安全修正後的真實 MoveIt/RViz 加 mock camera/serial 正式整合 8/8 通過，Docker Galactic 單元測試實際驗證 79/79 通過。實機仍未驗證；Z 不是已校正吸盤 TCP 或桌面淨空，沒有馬達位置回授，命令成功不代表實體到位。

## 1. 目前成果與狀態

### 1.1 本版操作契約

- 啟動依序執行 CM530 PING 與 HOME；HOME 成功且 worker 結束後才接受 R。HOME 或其他運動 worker 仍執行時，R 直接以 busy 拒絕，不覆蓋原 worker。
- R 呼叫 OpenCV，記錄 current 與 target；僅 current 驅動本版動作。
- current camera XY 映射為 base=(camera_y,-camera_x)，忽略相機 z。
- 先以 /compute_ik 求 z=0.05 m 接近姿態，再以 /plan_kinematic_path 從 HOME 或最後成功命令狀態規劃至接近點。
- 以 /compute_cartesian_path 從接近點固定 XY 與姿態垂降至 z=0.02 m，fraction 必須等於 1。
- 兩段完整驗證後合併多點軌跡；每一點 radians 嚴格轉換為 AX，超界即拒絕整條軌跡。
- RViz 接收完整多點 radians；CM530 paced 多點 BEGIN/PT/END 逐行等待精確 ACK，legacy 單點與 HOME 可接受 generic OK。
- ROS 等累計排程時間到達才送各 PT，最後 PT 收到 ACK 後才 END；ACK 過晚或等待晚喚醒均順延後續排程，不連發追趕或壓縮後續點間隔。CM530 韌體不變，仍忽略 dt_ms。
- RViz 失敗只警告；CM530 失敗立即嘗試 STOP、標記位置未知並鎖定 R，需重新啟動主控並成功 HOME。
- 所有 ACK 必須為完整 ASCII LF/CRLF 行，超過當次 ACK deadline 的回覆不接受；paced 多點另要求精確 id/seq。
- Ctrl+C 取消未送出點、由 worker 的取消路徑先嘗試 STOP，等待 worker 結束及停止清理後才關閉 serial；HOME I/O 或 ERR 故障也會 STOP、位置未知與鎖定。

### 1.2 驗證狀態

2026-09-04 安全修正後的正式 R 整合結果已保存於 ros2_main_control/test_results/multipoint_probe_final.json 與 .log，8/8 通過。使用真實 Galactic MoveIt/RViz 與 mock camera/serial，並非實機或實體相機測試。

八組完整軌跡點數為 [171,81,47,44,57,68,54,42]，命令時間毫秒為 [19447,9976,6845,6581,7651,8979,7425,6161]。所有最終 joint_states 誤差為 0 rad；下降 FK 的 max(|Δx|,|Δy|) 最大值為 0.00013191459849666576 m，約 0.132 mm，最終 z 約 0.020000 m。這些是模型與 fake controller 結果，不是硬體精度或到位證據。

本次 Docker 重新建置成功後，colcon test 實際驗證 79/79 通過，0 errors、0 failures、0 skipped；指令須帶 --merge-install。Windows 本機另完成 79 項，其中 52 通過、27 因無 ROS 而跳過。正式八組數據與證據路徑見第 14.7 節。上一版單點 IK/RViz 數據僅作歷史參考，不取代本次正式結果。

### 1.3 執行環境狀態

Docker、MoveIt、OpenCV 與 serial 狀態會隨啟停改變，每次操作依第 11、12 章重新檢查。正式 8/8 為 mock camera/serial 測試，不表示現場 OpenCV 相機、USB serial 或 CM530 已接通；不沿用舊的停止狀態或 Devices=[] 快照。

### 1.4 本版範圍與限制

本版結束於 current 的 base XY 所對應、end-effector link z=0.02 m 的命令終點。target 僅記錄，不前往 target、不控制 ESP32、不吸取或放置，也不自動上升或回 HOME。

相機外參與比例、AX 中心與方向、機械範圍、USB serial 映射及實機運動均需現場確認。桌面碰撞模型與吸盤 TCP 均未宣稱已校正；規劃座標不等於吸盤接觸面高度或桌面淨空。AX-12A present position 回讀與閉迴路到位確認尚未提供。

## 2. 系統架構與資料流

```text
R -> OpenCV current + target
  -> current XY: base=(camera_y,-camera_x)
  -> compute_ik: approach z=0.05 m
  -> plan_kinematic_path: command state -> approach
  -> compute_cartesian_path: approach -> z=0.02 m
  -> require fraction == 1
  -> validate BOTH stages, joint order and timing
  -> merge multi-point radians -> strict AX validation
  -> RViz: complete radians trajectory (best effort)
  -> CM530: BEGIN / timed PT points / END, exact ACKs
```

規劃起點是成功 HOME 對應的四軸命令，或上一筆完整成功命令的終點。這是 ROS 保存的命令狀態，不是 fake /joint_states 或實體馬達的測量值。只有整筆 CM530 命令成功後，才能將新終點作為下次 R 的規劃起點。

若設定 auto_home_on_startup=false，本版不會建立已知命令起點，因此仍會拒絕 R。必須重新啟動並啟用 startup HOME，成功完成 HOME 後才能要求動作。

接近與垂降必須全部規劃、合併及驗證成功，才開始此次 R 的任何 RViz 或 CM530 軌跡。即使接近路徑成功，垂降不完整也不得先移動到接近點。

RViz 顯示完整預期命令軌跡；實體沒有位置回授，不能從畫面或 ACK 判定到位。target 不參與規劃。

## 3. 重要目錄與檔案

### 3.1 Windows 專案路徑

```text
D:\畢業專題
├─ ros2_main_control
├─ OpenCV\OpenCV_ROS2_Bridge_test.01-main
├─ CM530\CM530_ROS_BRIDGE-main
├─ phantomx_pincher-ros2\phantomx_pincher-ros2
└─ docs
```

### 3.2 Docker ROS workspace

```text
/root/ws
├─ src
│  ├─ ros2_main_control
│  ├─ opencv_ros2_bridge_interfaces
│  └─ phantomx_pincher
├─ build
├─ install
└─ log
```

### 3.3 主控 package 檔案

| 檔案 | 用途 |
|---|---|
| `ros_main_controller.py` | ROS node、鍵盤、OpenCV、兩段規劃與 CM530 主流程 |
| `tabletop_mapping.py` | camera XY、REP103、固定 Z、yaw quaternion |
| `ax_mapping.py` | radians 與 AX position 雙向換算 |
| `cm530_protocol.py` | serial 協議、ACK、timeout、trajectory |
| `joint_state_utils.py` | 按指定 joint name 取出 IK radians |
| `future_utils.py` | 等待 ROS future 與 timeout |
| `moveit_trajectory_planner.py` | 接近與 Cartesian 垂降規劃 |
| `trajectory_utils.py` | 多點時間與合併軌跡驗證 |
| `motion_gate.py` | HOME 前或 CM530 失敗後禁止 R 動作 |
| `motion_mirror.py` | RViz 失敗不阻斷 CM530 的最佳努力流程 |
| `rviz_trajectory_sync.py` | FollowJointTrajectory goal、timeout 與結果判定 |
| `test/test_core.py` | 純 Python 核心單元測試 |
| `test/test_rviz_trajectory_sync.py` | ROS action 同步器單元測試 |
| `test/rviz_sync_probe.py` | fake controller 與 joint_states 整合探針 |
| `test/moveit_tabletop_ik_probe.py` | 歷史 8 點 MoveIt IK 探針 |
| `test/moveit_multipoint_probe.py` | mock camera/serial 與真實 MoveIt/RViz 八組完整 R 探針 |
| `launch/ros_main_controller.launch.py` | ROS2 launch 入口 |

## 4. 軟體與硬體需求

### 4.1 軟體

- Windows 與 Docker Desktop。
- WSL2，若相機或 USB serial 透過 WSL2 使用。
- Docker container：`mytest`。
- ROS2 Galactic：`/opt/ros/galactic`。
- ROS workspace：`/root/ws`。
- Python/ROS package：`rclpy`、`action_msgs`、`control_msgs`、`trajectory_msgs`、`geometry_msgs`、`sensor_msgs`、`moveit_msgs`、`opencv_ros2_bridge_interfaces`。
- Python serial：`python3-serial`。
- PhantomX MoveIt configuration。

### 4.2 硬體

- PhantomX Pincher 四軸手臂。
- AX-12A 馬達。
- CM530，正式規格的 Windows port 是 COM4。
- USB camera。
- ESP32 與吸盤模組目前可不接。

### 4.3 啟動前安全條件

- 手臂四周沒有障礙物、線材或人體。
- 首次實機只使用小幅度 AX 測試，不直接跑影像座標。
- 確認 CM530 電源、AX bus 與馬達 ID。
- RoboPlus Terminal、手動 Python serial 工具與 ROS 主控不能同時開啟同一個 serial port。
- 準備實體斷電方式。CM530 `STOP` 不是斷電急停。

## 5. OpenCV service 介面

### 5.1 Service 名稱與型別

```text
Service name: /camera/get_object_point
Service type: opencv_ros2_bridge_interfaces/srv/GetObjectPoint
```

實際 `.srv`：

```text
# request 無欄位
---
bool success
string message
geometry_msgs/Point current_position
geometry_msgs/Point target_position
```

不要使用舊 README 所描述的 `source + geometry_msgs/PointStamped` 作為此 service 的 response。`PointStamped` 屬於其他 topic 或文字橋接輸出。

### 5.2 座標定義

- `current_position`：要夾取的橘色圓形中心。
- `target_position`：要放置的空黑色方塊中心。
- 單位：公尺。
- 原點：影像中心。
- camera x：影像向右為正。
- camera y：影像向上為正。
- z：固定為 `0.0`，主控會忽略。
- 預設 `scale_px_per_meter=100.0`，必須以實際桌面尺寸校正。

像素轉 camera XY 的公式：

```text
camera_x = (pixel_x - image_width / 2) / scale_px_per_meter
camera_y = (image_height / 2 - pixel_y) / scale_px_per_meter
```

### 5.3 配對邏輯

- `current_position` 選擇離畫面中心最遠的橘色圓。
- `target_position` 選擇離畫面中心最近的空黑色方塊。
- 找不到橘色圓時可能回覆 `no orange circle detected`。
- 沒有空黑方塊時可能回覆 `all black squares are occupied`。
- 無有效配對時可能回覆 `no valid pair`。

## 6. 桌面座標與 IK

### 6.1 預設 REP103 映射

因為鏡頭俯視桌面，並假設影像上方對應手臂前方：

```text
base_x = camera_y
base_y = -camera_x
base_z = 0.05
```

範例：

```text
camera_xy = (0.0303, 0.0685)
base_xyz  = (0.0685, -0.0303, 0.05)
```

若相機輸出已經和手臂 base 軸向一致，可把 `xy_mapping` 改為 `camera_xy_direct`：

```text
base_x = camera_x
base_y = camera_y
```

### 6.2 高度

- OpenCV service z 一律忽略。
- `target_z_offset_m` 預設是 `0.05 m`。
- 接近高度使用 `target_z_offset_m=0.05`；垂降終點使用 `pickup_z_m=0.02`。
- `min_target_z_m=0.02` 是最低目標 Z 保護值；參數組合必須允許由接近高度下降至拾取高度。
- Z 指 phantomx_pincher_end_effector link 相對 phantomx_pincher_arm_base_link 的座標，不是相機量到的距離，也不是吸盤 TCP 高度。
- 桌面碰撞模型、桌面相對 base 高度與吸盤 TCP 尚需校正；z=0.02 m 不代表距實際桌面 2 cm。
- `target_z_offset_m` 雖含 target 字樣，本版用於 current 的接近高度，與 target 放置無關。

### 6.3 End-effector 姿態

```text
yaw = atan2(base_y, base_x)
orientation = qz(yaw) * [1, 0, 0, 0]
```

預設 base orientation 是 `[x,y,z,w]=[1,0,0,0]`。使用 Hamilton quaternion 左乘後：

```text
qx = cos(yaw / 2)
qy = sin(yaw / 2)
qz = 0
qw = 0
```

舊版 8 點 IK 探針記錄固定 `[0,0,0,1]` 姿態為 0/8、yaw-aligned 為 8/8；此歷史結果不能證明新版接近路徑或 z=0.02 m 垂降可行。

### 6.4 MoveIt 設定

```text
IK service: /compute_ik
Planning group: arm
Base link: phantomx_pincher_arm_base_link
End effector: phantomx_pincher_end_effector
Solver: lma_kinematics_plugin/LMAKinematicsPlugin
```

四軸 joint order：

```text
1. phantomx_pincher_arm_shoulder_pan_joint
2. phantomx_pincher_arm_shoulder_lift_joint
3. phantomx_pincher_arm_elbow_flex_joint
4. phantomx_pincher_arm_wrist_flex_joint
```

### 6.5 兩段規劃與預先驗證

先呼叫 /compute_ik 取得接近姿態的四軸解，再用 /plan_kinematic_path 從保存的命令狀態規劃到該解。首次起點由 HOME AX [512,512,512,512] 按相同校正反算 radians；後續起點是最後成功命令終點。

以接近路徑終點作為 /compute_cartesian_path 起點，保持 current 的 base XY 及末端姿態，垂直下降至 pickup_z_m。服務必須成功且 fraction == 1；小於 1 的部分路徑一律拒絕。服務缺失、逾時、錯誤碼失敗或空軌跡均不得送出此次 R 的軌跡。

合併前檢查兩段的 joint names、四軸資料、有限數值、接點連續性與時間；Cartesian 的局部時間須接到接近段之後。合併後保留完整多點序列，不能只取最後一點。

### 6.6 軌跡時間

接近段使用 MoveIt 規劃時間；速度與加速度比例分別由 trajectory_velocity_scale 與 trajectory_acceleration_scale 控制，兩者預設 0.25。

Galactic 的 Cartesian service 已實測會回傳有效時間戳，但介面不支援這兩個縮放參數。對有效且嚴格遞增的垂降時間，ROS 端乘上 max(1/velocity_scale, 1/sqrt(acceleration_scale))，其中 velocity_scale 與 acceleration_scale 分別指上述兩個參數；預設乘數為 max(4,2)=4。這是延長有效時間的處理，與全部零時間的補時分開。

Cartesian 只有在所有 time_from_start 都是零時，才依相鄰點四軸角度差與 joint_velocity_limits 補時。依目前實作，每段秒數取所有關節 abs(delta_q)/(limit * trajectory_velocity_scale) 的最大值，向上取整為毫秒且至少 1 ms，再累積成有效時間軸。四軸 limits 預設均為 0.52359878 rad/s；預設速度比例為 0.25。

含非零時間的軌跡必須嚴格遞增；重複或倒退的非零時間序列拒絕，不以補時掩蓋。首個零時間可表示規劃起點，合併後會移除此零時起點；真正送出的第一點時間必須大於零。合併點的重複起點與時間必須由合併流程正確處理。

motion_dt_ms=300 僅控制 HOME 的 RViz 動畫，不提供 R 的接近、垂降或 PT 固定間隔。補時與速度比例是命令排程依據，不設定 AX-12A 實際速度。

## 7. AX12A position 轉換

每一軸使用：

```text
ax = center + sign * radians * scale
center = [512, 512, 512, 512]
sign   = [1, 1, 1, 1]
scale  = 195.3786081396107 counts/radian
```

每一個合併軌跡點都必須先完成四軸順序與有限數值檢查，再嚴格轉換為整數 AX position。任何超出 0..1023 的計算值都拒絕整條軌跡，不可用 clamp 把超界值壓回合法範圍。全部點通過前不送 RViz goal 或 CM530 BEGIN。

合法 AX 數值只代表格式與設定範圍合法，不保證機械極限、桌面淨空或碰撞安全。中心、方向與比例需校正。HOME 的 [512,512,512,512] 亦依同一組校正反算為視覺及規劃起點。

舊版單點範例僅供換算對照：

```text
camera_xy = (0.0303, 0.0685)
approach  = (0.0685, -0.0303, 0.05)
radians   = [-0.4165, -0.2334, 1.9790, 1.3968]
AX        = [431, 466, 899, 785]
```

此例不是垂降終點，也不是新版規劃測試結果。

## 8. CM530 serial 協議

### 8.1 通訊設定

```text
Windows port: COM4
Container target: /dev/ttyUSB0
Baudrate: 57600
Data bits: 8
Parity: none
Stop bits: 1
Flow control: none
Encoding: ASCII
ROS line ending: LF (\n)
```

CM530 開機會輸出一次 `READY`。主控開啟 serial 後清空 input buffer，並在等待 ACK 時忽略 `READY`。所有命令的 ACK 都必須是 ASCII 完整行，以 LF 或 CRLF 結尾；分段讀取須累積至 LF 才判讀，沒有行尾的片段不算成功。非 ASCII 回覆會失敗，超過當次命令 ACK deadline 才讀回的資料不接受。此逾時檢查不等於協議具備跨連線的新鮮度或防重播保證。

### 8.2 固定馬達順序

CM530 正式規格：

```text
j1 -> ID17
j2 -> ID3
j3 -> ID2
j4 -> ID15
```

ROS 端只傳四個 AX position，實體 ID 對應由 CM530 韌體負責。

### 8.3 主控使用的命令

| 命令 | 成功回覆 | 用途 |
|---|---|---|
| `PING` | `PONG` | 確認 serial 通訊 |
| `HOME` | `OK,HOME` | 四軸送到 512 |
| `BEGIN,<id>,4,<count>` | `OK,BEGIN,<id>` | 開始軌跡 |
| `PT,<seq>,<dt>,<j1>,<j2>,<j3>,<j4>` | `OK,PT,<seq>` | 傳一個四軸目標 |
| `END,<id>` | `OK,END,<id>` | 完成軌跡 |
| `STOP` | `OK,STOP` | 保持最後目標位置 |

主控採一問一答。R 的 paced 多點 BEGIN/PT/END 每行等待精確 ACK，BEGIN/END 的 id 與 PT 的 seq 必須完全符合，不能以 generic OK 代替。N 為合併後總點數，PT 按序號依序傳送。此強制 exact 規則僅適用於 paced 多點路徑；既有單點與 HOME legacy 路徑仍可接受 generic OK，不可宣稱所有命令都拒絕 generic OK。

ROS 側先等待累計排程時間到達，才送該點 PT。以 BEGIN 收到 ACK 後的 monotonic 時間為起點，第一 PT 在 dt0 時間送，第二 PT 在 dt0+dt1 時間送，之後依序累加。最後點也須等到其預定時間才送，收到最後 PT ACK 後才能 END，不能先送 PT 再等待。

dt_ms 表達相鄰點時間差；CM530 韌體忽略此欄位，收到 PT 即套用目標。因此等待責任在 ROS。若 ACK 晚到導致下一點 deadline 已過，實作會從目前時間再加上該點 dt_ms，後續 deadline 沿延長後的排程累加。若 sleep 或取消事件等待晚喚醒，也會以實際 monotonic 時間更新 deadline，把偏移順延至所有後續點，不壓縮下段點間隔或突發追趕過期點。

例：dt=[100,200,300] 時，無逾期下於 BEGIN ACK 後 100、300、600 ms 送三點；若第一點晚喚醒至 150 ms，且沒有其他延遲，後續改為 350、650 ms。最後 ACK 後 END；這是送出時序，不是實體到位承諾。

CM530 任一步失敗（包含該路徑判定不合格的 ACK、ERR、逾時或 serial 例外），立即中止後續點並嘗試 STOP，將位置標記未知、鎖定 R。STOP 成功也不恢復已知位置；排除故障後必須重新啟動主控並成功 HOME。命令成功不等於實體到位。

啟動 PING/HOME 的 I/O、ERR 或 ACK 失敗亦適用 STOP 與位置未知鎖定流程；HOME 失敗不能只記錄錯誤後允許 R。所有 STOP 都是嘗試，serial 故障時不能保證送達。

### 8.4 錯誤碼

| 回覆 | 意義 |
|---|---|
| `ERR,BAD_CMD` | 未知命令 |
| `ERR,BAD_ARG` | 參數數量或整數格式錯誤 |
| `ERR,RANGE` | position 不在 `0..1023` |
| `ERR,BAD_TRAJ` | BEGIN/PT/END 狀態或數量錯誤 |
| `ERR,DXL_TX` | AX-12A SYNC_WRITE 失敗 |
| `ERR,DXL_TORQUE,<id>` | 指定馬達 torque enable 失敗 |
| `ERR,OVERFLOW` | 單行命令超過 buffer |

> `STOP` 不會關 torque、不會回 HOME，也不是斷電急停。真正危險時使用硬體斷電。

### 8.5 RViz fake controller 同步

主控使用 ROS2 action：

```text
Action name: /joint_trajectory_controller/follow_joint_trajectory
Action type: control_msgs/action/FollowJointTrajectory
```

R 動作沿用主控四軸 joint_names，positions 與 time_from_start 取自預先驗證後的完整合併軌跡；RViz 接收全部點，不能縮成單一終點或統一 300 ms。

兩段規劃、時間及 AX 轉換全部成功後，先發起 RViz goal，再執行對應 CM530 多點傳送，最後檢查 RViz 結果。RViz action 不存在、拒絕、逾時或失敗只警告，不阻擋或中止 CM530。

啟動 HOME 用 ax_to_radians([512,512,512,512]) 取得視覺 HOME。motion_dt_ms 預設 300 僅用於 HOME 動畫；若為 0，RViz 動畫至少使用 1 ms。CM530 仍使用獨立 HOME 命令。motion gate 只以 CM530 HOME 成功建立可操作狀態。

RViz 成功要求 server 可用、goal accepted、status 為 SUCCEEDED、result error code 為 SUCCESSFUL。CM530 失敗時仍須立即 STOP、標記位置未知並鎖定 R，不能等待 RViz 成功來解鎖。已送出的 RViz 動畫可能繼續，畫面不能用於故障後定位。

## 9. 主控節點參數

| 參數 | 預設值 | 用途 |
|---|---|---|
| `camera_service` | `/camera/get_object_point` | OpenCV service |
| `ik_service` | `/compute_ik` | 接近姿態 IK |
| `planning_service` | `/plan_kinematic_path` | 至接近點的完整路徑 |
| `cartesian_path_service` | `/compute_cartesian_path` | 接近點至拾取高度的垂降 |
| `serial_port` | `/dev/ttyUSB0` | 容器內 CM530 serial |
| `serial_baudrate` | `57600` | serial baudrate |
| `serial_timeout_sec` | `2.0` | ACK timeout |
| `auto_home_on_startup` | `true` | 啟動後 PING 與 HOME；false 缺少已知起點，R 仍拒絕 |
| `planning_group` | `arm` | MoveIt planning group |
| `base_link` | `phantomx_pincher_arm_base_link` | IK pose frame |
| `end_effector` | `phantomx_pincher_end_effector` | IK link |
| `joint_names` | 四軸固定名稱 | IK 結果抽取順序 |
| `ik_timeout_sec` | `1.0` | MoveIt IK timeout |
| `ik_avoid_collisions` | `false` | IK collision check |
| `xy_mapping` | `rep103_base_link` | camera XY 到 base XY |
| `target_z_offset_m` | `0.05` | end-effector link 的 base Z 接近值 |
| `pickup_z_m` | `0.02` | end-effector link 的 base Z 終點 |
| `min_target_z_m` | `0.02` | 最低目標 Z，公尺 |
| `planning_timeout_sec` | `5.0` | 規劃逾時，秒 |
| `cartesian_max_step_m` | `0.002` | Cartesian 最大步長，公尺 |
| `trajectory_velocity_scale` | `0.25` | 接近規劃及有效垂降時間縮放 |
| `trajectory_acceleration_scale` | `0.25` | 接近規劃及有效垂降時間縮放 |
| `joint_velocity_limits` | 四軸均為 `0.52359878` | Cartesian 全零時間補時，rad/s |
| `motion_dt_ms` | `300` | 僅 HOME 的 RViz 動畫 |
| `rviz_sync_enabled` | `true` | 是否送 fake controller action |
| `rviz_trajectory_action` | `/joint_trajectory_controller/follow_joint_trajectory` | RViz trajectory action |
| `rviz_action_server_timeout_sec` | `0.25` | 等待 action server 時間 |
| `rviz_action_result_timeout_sec` | `2.0` | goal acceptance 與 result timeout |
| `orientation_xyzw` | `[1,0,0,0]` | 基礎 end-effector 姿態 |
| `yaw_aligned_orientation` | `true` | 是否依 XY 對齊 yaw |
| `ax_centers` | `[512,512,512,512]` | 每軸 AX 中心 |
| `ax_signs` | `[1,1,1,1]` | 每軸方向 |
| `ax_scale` | `195.3786081396107` | radians 到 AX 比例 |

以上新增參數為本版批准預設值，使用前以重新建置的節點確認已提供。joint_velocity_limits 完整值為 [0.52359878,0.52359878,0.52359878,0.52359878]，順序同四軸 joint_names。其用途是補時，不能當作馬達實際速度保證。

參數覆寫範例：

```bash
ros2 run ros2_main_control ros_main_controller --ros-args \
  -p serial_port:=/dev/ttyUSB0 \
  -p xy_mapping:=rep103_base_link \
  -p target_z_offset_m:=0.05 \
  -p pickup_z_m:=0.02 \
  -p min_target_z_m:=0.02 \
  -p rviz_sync_enabled:=true \
  -p rviz_trajectory_action:=/joint_trajectory_controller/follow_joint_trajectory \
  -p yaw_aligned_orientation:=true \
  -p orientation_xyzw:="[1.0,0.0,0.0,0.0]" \
  -p ax_centers:="[512,512,512,512]" \
  -p ax_signs:="[1,1,1,1]"
```

## 10. 首次部署與建置

### 10.1 確認容器

在 Windows PowerShell：

```powershell
docker ps -a --filter name=mytest
docker start mytest
docker exec mytest bash -lc "ls /opt/ros/galactic"
```

### 10.2 將 package 同步到容器

現有 container 已有檔案時，可同步內容：

```powershell
docker cp "D:\畢業專題\ros2_main_control\." `
  "mytest:/root/ws/src/ros2_main_control"

docker cp "D:\畢業專題\OpenCV\OpenCV_ROS2_Bridge_test.01-main\opencv_ros2_bridge_interfaces\." `
  "mytest:/root/ws/src/opencv_ros2_bridge_interfaces"
```

### 10.3 安裝 serial dependency

進入容器：

```bash
docker exec -it mytest bash
apt-get update
apt-get install -y python3-serial
```

如果容器已能執行 `python3 -c "import serial"`，不需重複安裝。

### 10.4 建置

在容器中：

```bash
source /opt/ros/galactic/setup.bash
cd /root/ws
colcon build --merge-install \
  --packages-select opencv_ros2_bridge_interfaces ros2_main_control
source /root/ws/install/setup.bash
```

預期：

```text
Summary: 2 packages finished
```

### 10.5 每個新 terminal 都要 source

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
```

沒有 source 時常見症狀是找不到 package、service type 或 executable。

## 11. 將 CM530 USB serial 提供給容器

先以 docker inspect mytest 檢查目前 device mapping。若 Devices=[] 且沒有其他裝置提供方式，需依環境處理 serial 存取；不要把上一版環境快照當作本次狀態。

### 11.1 Windows + WSL2

1. 關閉 RoboPlus Terminal 與所有使用 COM4 的程式。
2. 保持一個 WSL terminal 開啟。
3. 管理員 PowerShell 列出 USB：

```powershell
usbipd list
```

4. 找到 CM530 USB serial 的 `<BUSID>`，第一次使用時分享裝置：

```powershell
usbipd bind --busid <BUSID>
```

5. 將裝置 attach 到 WSL2：

```powershell
usbipd attach --wsl --busid <BUSID>
```

6. 在 WSL 確認 Linux device name：

```bash
lsusb
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Microsoft 說明指出，USB attach 到 WSL 時 Windows 不能同時使用該裝置。完成後可用：

```powershell
usbipd detach --busid <BUSID>
```

官方參考：[Microsoft WSL USB 裝置](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)

### 11.2 將 Linux device 加入 Docker container

Docker 使用 `--device=<host-device>:<container-device>`。例如：

```bash
docker run ... \
  --device=/dev/ttyUSB0:/dev/ttyUSB0 \
  andrejorsula/phantomx_pincher:latest
```

官方參考：[Docker `--device`](https://docs.docker.com/reference/cli/docker/container/run/#add-host-device-to-container---device)

現有 container 不能靠重新啟動自動增加建立時沒有的 device mapping。重建前先記錄原設定：

```powershell
docker inspect mytest
```

上一版環境設定範例，重建前須用本次 inspect 結果核對：

```text
Image: andrejorsula/phantomx_pincher:latest
WorkingDir: /root/ws
Tty/OpenStdin: true
Privileged: false
NetworkMode: bridge
Bind: /tmp/.X11-unix:/tmp/.X11-unix:rw
Bind: /workspace/phantomx_pincher:/root/ws/src/phantomx_pincher
Devices: []
```

建議先建立另一個測試 container 驗證 device，不直接刪除 `mytest`。重建後，複製進 container writable layer 的 `ros2_main_control` 與 interface package 要再次同步與建置。

### 11.3 驗證 serial

```powershell
docker exec mytest bash -lc "ls -l /dev/ttyUSB* /dev/ttyACM*"
docker exec mytest python3 -c "import serial; print(serial.__version__)"
```

確認實際名稱後，把主控的 `serial_port` 改成該裝置，例如 `/dev/ttyACM0`。

## 12. 每日標準啟動流程

### 12.1 步驟 0：安全檢查

- 清空手臂工作區。
- 確認拼圖片座標落在已測試範圍。
- 確認實體斷電方式可立即操作。
- 關閉 RoboPlus Terminal 與手動 serial 程式。
- 確認 CM530 serial 已映射進容器。

### 12.2 步驟 1：啟動 container

Windows PowerShell：

```powershell
docker start mytest
docker ps --filter name=mytest
```

### 12.3 步驟 2：啟動 PhantomX MoveIt

開啟第一個互動 terminal：

```powershell
docker exec -it mytest bash
```

容器內：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 launch phantomx_pincher fake.launch.py log_level:=error
```

此 launch 會同時啟動 MoveIt、fake ros2_control、joint trajectory controller、joint state broadcaster 與 RViz。另一個 terminal 驗證：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 service list -t | grep -E 'compute_ik|plan_kinematic_path|compute_cartesian_path'
ros2 action list -t | grep /joint_trajectory_controller/follow_joint_trajectory
ros2 control list_controllers
```

預期：

```text
/compute_ik [moveit_msgs/srv/GetPositionIK]
/plan_kinematic_path [moveit_msgs/srv/GetMotionPlan]
/compute_cartesian_path [moveit_msgs/srv/GetCartesianPath]
/joint_trajectory_controller/follow_joint_trajectory [control_msgs/action/FollowJointTrajectory]
joint_trajectory_controller[...] active
```

若刻意只啟動 MoveIt、不啟動 fake controller，主控仍可驅動 CM530，但會看到 RViz 同步 warning。也可在主控加入 `-p rviz_sync_enabled:=false` 完全關閉同步。

### 12.4 步驟 3：啟動 OpenCV pick-and-place

在原本可執行 OpenCV ROS2 的 WSL2 terminal，先 source 該環境中已建置 `opencv_ros2_bridge_interfaces` 的 workspace，再執行：

```bash
cd "/mnt/d/畢業專題/OpenCV/OpenCV_ROS2_Bridge_test.01-main"
./start_pp.sh
```

等效核心參數：

```bash
python3 camera_point_cv_subscriber.py --ros-args \
  -p processing_mode:=pick-and-place \
  -p black_s_max:=255 \
  -p black_v_max:=120 \
  -p black_max_area:=200000.0
```

在 container 內驗證：

```bash
ros2 service list -t | grep /camera/get_object_point
```

預期：

```text
/camera/get_object_point [opencv_ros2_bridge_interfaces/srv/GetObjectPoint]
```

若跨 WSL/container 找不到 service，確認雙方 `ROS_DOMAIN_ID` 相同：

```bash
echo $ROS_DOMAIN_ID
```

### 12.5 步驟 4：啟動主控節點

必須使用互動 terminal，否則無法按 `R`：

```powershell
docker exec -it mytest bash
```

容器內：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 run ros2_main_control ros_main_controller --ros-args \
  -p serial_port:=/dev/ttyUSB0
```

正常啟動預期看到：

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

如果只看到 `Failed to open CM530 serial port`，不要按 `R`，先處理第 11 章。

### 12.6 步驟 5 按 R 執行兩段動作

確認 HOME 成功、相機座標合理、三個 MoveIt service 均可用，並已完成現場校正後，在主控互動 terminal 按 R。

預期事件順序如下，這是驗收流程，不是本次實測日誌：

1. 取得 OpenCV current/target，記錄原始值。
2. current XY 映射到 base，設定接近 z=0.05 與拾取 z=0.02。
3. /compute_ik 解接近姿態。
4. /plan_kinematic_path 從保存命令狀態規劃至接近點。
5. /compute_cartesian_path 垂降，確認成功與 fraction == 1。
6. 完整驗證兩段、時間、四軸順序與所有 AX，合併為多點軌跡。
7. 向 RViz 發起完整多點 goal。
8. CM530 BEGIN id,4,N 收到 ACK 後開始計時；各 PT 等累計時間到達才送，每行核對精確 ACK；最後 PT ACK 後才 END id。ACK 過晚則延長排程，不連發追趕。
9. 完整 CM530 成功後保存命令終點；檢查 RViz 結果，warning 不影響實體命令成功。

接近或垂降任一步規劃或驗證失敗，都不得開始此次 R 的 RViz 或 CM530 軌跡。CM530 失敗立即 STOP、位置未知、R 鎖定；重新啟動主控並 HOME 才能恢復。不得因 RViz 顯示在終點而繼續送點。

此流程終點僅為 current 的 z=0.02 m 命令位置，沒有吸盤、target 放置或自動返回。再次按 R 會從最後成功命令狀態重新規劃；該狀態未經實體位置回授確認。

## 13. 正常停止流程

### 13.1 停止主控

在主控 terminal 按 Ctrl+C。shutdown 設定取消事件並標記位置未知，拒絕新 R；worker 在各未送出點與 END 前檢查取消，定時等待也可被取消事件喚醒。軌跡因取消中止時，worker 先經故障路徑嘗試 STOP。

主控等待 worker 結束，再於 serial 仍開啟時補做 STOP 清理；之後停止 keyboard watcher、清理 RViz，最後關閉 serial 與 ROS node。HOME 在送出前後也檢查取消，I/O 或 ERR 失敗立即經 STOP 與位置未知鎖定處理。

正在進行的 serial 讀取可能仍要等回覆或 timeout 才返回。不要把 Ctrl+C 當作即時硬體急停，也不要以強制關閉 serial 取代 worker 停止流程；危險時使用硬體斷電。

### 13.2 停止 OpenCV

在 OpenCV terminal 按 `Ctrl+C`，確認相機資源釋放。

### 13.3 停止 MoveIt

在 MoveIt terminal 按 `Ctrl+C`。

### 13.4 停止 container

確認沒有需要保存的 container 內程序後：

```powershell
docker stop mytest
```

### 13.5 危險或失控時

1. 不要依賴 terminal 操作。
2. 使用硬體斷電。
3. 清除原因後再重新上電與 HOME。

## 14. 測試手冊

### 14.1 本機純 Python 單元測試

Windows PowerShell：

```powershell
cd "D:\畢業專題"
python -m unittest discover -s ros2_main_control\test -v
```

2026-09-04 Windows 本機重新執行共 79 項：52 通過、27 跳過。跳過原因為本機無 ROS，無法執行依賴 ROS messages/action 的測試；完整 ROS 相依驗證以第 14.2 節 Docker 結果為準。

### 14.2 Docker 單元測試

進入 mytest，在已重新建置的 Galactic workspace 執行：

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
cd /root/ws
colcon test --merge-install --packages-select ros2_main_control \
  --event-handlers console_direct+
```

setup.py 已加入 tests_require=["pytest"]，package.xml 已加入 python3-pytest 測試相依。一般 colcon test 現在會執行 pytest；此 workspace 使用合併安裝，測試也必須帶 --merge-install。

2026-09-04 Docker 重新建置後實際驗證 79/79 通過，0 errors、0 failures、0 skipped，涵蓋核心換算、多點規劃、時間、ACK、RViz 同步、主控故障流程及測試相依設定。新增兩個 race 回歸案例均經 red/green 修復：HOME 未結束時拒絕 R 且不覆蓋 worker，以及晚喚醒偏移順延全部後續點。單元測試使用替身的故障案例，不代表實體硬體故障復原已驗證。

### 14.3 Docker 建置測試

```bash
source /opt/ros/galactic/setup.bash
cd /root/ws
colcon build --merge-install \
  --packages-select opencv_ros2_bridge_interfaces ros2_main_control
```

本次 Docker 重新建置成功，其後第 14.2 節的 colcon test 實際收集並通過全部 79 項測試。建置成功不代表 CM530 實機或桌面碰撞／TCP 校正已完成。

### 14.4 MoveIt 8 點 IK 探針

先啟動 MoveIt，接著：

```powershell
docker exec -w /root/ws mytest bash -lc `
  "source /opt/ros/galactic/setup.bash && source /root/ws/install/setup.bash && python3 src/ros2_main_control/test/moveit_tabletop_ik_probe.py"
```

舊版歷史結果，僅驗證接近高度 IK，不取代第 14.7 節完整路徑驗證：

| camera_xy | base_xyz | AX |
|---|---|---|
| `(0.0303,0.0685)` | `(0.0685,-0.0303,0.0500)` | `[431,466,899,785]` |
| `(0.0248,0.1268)` | `(0.1268,-0.0248,0.0500)` | `[474,574,787,789]` |
| `(0.0233,0.0992)` | `(0.0992,-0.0233,0.0500)` | `[467,521,850,779]` |
| `(0.0041,0.0911)` | `(0.0911,-0.0041,0.0500)` | `[503,500,870,780]` |
| `(-0.0373,0.1108)` | `(0.1108,0.0373,0.0500)` | `[575,550,817,783]` |
| `(0.0331,0.1005)` | `(0.1005,-0.0331,0.0500)` | `[450,528,842,780]` |
| `(-0.0172,0.1193)` | `(0.1193,0.0172,0.0500)` | `[540,557,809,784]` |
| `(-0.0166,0.1222)` | `(0.1222,0.0166,0.0500)` | `[538,562,802,786]` |

預期最後一行：

```text
SUMMARY: 8/8 IK solved
```

### 14.5 RViz action 與 joint_states 探針

先以 `fake.launch.py` 啟動 MoveIt 與 fake controller，再執行：

```powershell
docker exec -w /root/ws mytest bash -lc `
  "source /opt/ros/galactic/setup.bash && source /root/ws/install/setup.bash && PYTHONPATH=/root/ws/src/ros2_main_control:`$PYTHONPATH python3 src/ros2_main_control/test/rviz_sync_probe.py"
```

舊版單點探針歷史輸出，未於本次重新執行：

```text
RVIZ_SYNC_PROBE_OK target=[0.1, -0.15, 0.2, -0.1] actual=[0.099514, -0.149271, 0.199028, -0.099514] max_error=0.000972
```

最大誤差必須小於 `0.02 rad`。這個結果證明 fake controller 接收相同四軸 radians 並更新 `/joint_states`，不代表實體 AX-12A 已到位。

### 14.6 CM530 實機測試順序

不要一開始就接完整 OpenCV 流程。依序進行：

1. `PING -> PONG`。
2. `HOME -> OK,HOME`。
3. 小幅 `AX,520,512,512,512`。
4. 小幅三點 trajectory：512 -> 520 -> 512。
5. 確認各軸方向與中心。
6. 再啟用主控與 OpenCV。

Windows 手動工具：

```powershell
cd "D:\畢業專題\CM530\CM530_ROS_BRIDGE-main\15 cm530 test"
python manual_position_terminal.py --port COM4 --baud 57600
```

同一時間只能有這個工具或 ROS 主控其中一個開啟 COM4。

### 14.7 正式八組完整 R 整合結果

在已 source 的 Galactic workspace，先啟動 MoveIt 與 RViz fake controller，再執行：

```bash
python3 src/ros2_main_control/test/moveit_multipoint_probe.py
```

探針提供 mock camera service 與 mock serial，呼叫主控 R 的請求流程；規劃、Cartesian 與 FK 使用真實 MoveIt，joint_states 來自 RViz fake controller。本測試沒有連接真實相機或 CM530，也不是實體按鍵操作驗證。

正式 JSON 與 log 已核對：

```text
D:\畢業專題\ros2_main_control\test_results\multipoint_probe_final.json
D:\畢業專題\ros2_main_control\test_results\multipoint_probe_final.log
SUMMARY {"passed": 8, "total": 8}
```

最後兩個 race 修正後重新執行的八組整合已正常結束，exit 0、8/8 通過，各組最終 joint_states 誤差均為 0 rad。第一組最終 AX 為 [431,489,943,718]。命令時間為合併軌跡最後 time_from_start，並非包含 ACK 延遲的實際牆鐘執行時間，也不是到位時間。

| 組別 | 點數 | 命令時間 ms | 下降 XY 誤差 mm | 終點 Z m |
|---|---|---|---|---|
| 1 | 171 | 19447 | 0.071227 | 0.020000057 |
| 2 | 81 | 9976 | 0.089822 | 0.020000160 |
| 3 | 47 | 6845 | 0.082503 | 0.020000113 |
| 4 | 44 | 6581 | 0.109061 | 0.020000093 |
| 5 | 57 | 7651 | 0.075058 | 0.020000138 |
| 6 | 68 | 8979 | 0.087696 | 0.020000128 |
| 7 | 54 | 7425 | 0.116625 | 0.020000156 |
| 8 | 42 | 6161 | 0.131915 | 0.020000148 |

下降 XY 誤差逐點以 max(|Δx|,|Δy|) 計算，不是 XY 歐氏距離；八組最大值為 0.00013191459849666576 m，約 0.132 mm。FK 終點 Z 範圍為 0.0200000575 至 0.0200001604 m。數據表小數為四捨五入，完整精度以 JSON 為準。

FK 的對象為 phantomx_pincher_end_effector link，相對 phantomx_pincher_arm_base_link。尚未建立吸盤 TCP 或桌面碰撞模型已校正的證據，不能將此數字解讀為吸盤距桌面、實際接觸高度或硬體追蹤精度。

### 14.8 驗證覆蓋與實機限制

正式八組覆蓋成功路徑；本次 Docker 實際驗證 79 個 Galactic 單元測試全部通過。下表區分這兩類證據與剩餘實機／專項驗證，不以成功軌跡測試取代全部故障案例。

| 項目 | 狀態 | 證據與限制 |
|---|---|---|
| 接近加垂降 | 整合通過 | 正式 8/8，真實 MoveIt/RViz 加 mock camera/serial |
| 部分或錯誤規劃 | 單元通過 | 部分 Cartesian、錯誤時間、錯誤起點等拒絕案例 |
| 嚴格 AX 與四軸 | 單元及整合通過 | 單元檢查超界；整合逐點核對 AX 與點數 |
| 全零 Cartesian 時間 | 單元通過 | 依 limit * velocity_scale 補時 |
| 有效垂降時間縮放 | 單元及整合通過 | 有效時間按公式延長，預設 4 倍 |
| 非遞增時間 | 單元通過 | 重複或倒退時間拒絕 |
| ROS 定時 | 單元及整合通過 | 先等時間再 PT，最後 PT ACK 後 END；晚喚醒順延有回歸測試，ACK 延遲壓力仍待專項驗證 |
| HOME worker 所有權 | 單元通過 | HOME 未結束時 R 以 busy 拒絕，不覆蓋 worker；新增 red/green 回歸案例 |
| ACK 格式與逾時 | 單元通過 | ASCII、完整行、deadline、paced 精確匹配；legacy generic OK 相容 |
| 完整 RViz goal | 單元及整合通過 | 八組全部多點，最終 joint_states 誤差全 0 rad |
| RViz 失敗隔離 | 單元通過 | 同步失敗不阻擋 CM530 路徑 |
| CM530 與 HOME 故障 | 單元通過 | I/O 等替身故障測試；STOP、unknown、R 鎖定，非實機故障測試 |
| Ctrl+C 停止 | 單元覆蓋 | 取消未送點與 worker／serial 清理順序；真實硬體取消未驗證 |
| 復原與到位 | 實機待驗證 | STOP 不恢復位置回授，需重啟 HOME；無硬體到位證據 |
| 桌面與吸盤 TCP | 待校正 | 不宣稱碰撞模型或 TCP 已校正，Z 是 link 對 base 座標 |

## 15. 常見問題與排除

### 15.1 `Failed to open CM530 serial port`

可能原因：

- 容器沒有 `/dev/ttyUSB0`。
- 實際名稱是 `/dev/ttyACM0`。
- container 建立時沒有 `--device`。
- RoboPlus 或其他程式占用 COM4。
- USB 未 attach 到 WSL2。

檢查：

```bash
ls -l /dev/ttyUSB* /dev/ttyACM*
python3 -c "import serial; print(serial.__version__)"
```

### 15.2 `Camera service not available`

```bash
ros2 service list -t | grep camera
ros2 interface show opencv_ros2_bridge_interfaces/srv/GetObjectPoint
echo $ROS_DOMAIN_ID
```

確認 OpenCV 使用 `processing_mode:=pick-and-place`，並已 source interface workspace。

### 15.3 OpenCV 回覆失敗

- `no orange circle detected`：調整橘色 HSV、面積或光線。
- `all black squares are occupied`：檢查黑方塊門檻與 occupancy 判定。
- `no valid pair`：確認畫面同時存在可夾取橘圓與空黑方塊。

### 15.4 MoveIt service 不存在

```bash
ros2 service list -t | grep -E 'compute_ik|plan_kinematic_path|compute_cartesian_path'
ps -ef | grep move_group
```

重新啟動 `ros2 launch phantomx_pincher fake.launch.py`。

### 15.5 IK code `-31`

`-31` 是無 IK 解。檢查：

- 是否使用 `orientation_xyzw=[1,0,0,0]`。
- `yaw_aligned_orientation` 是否為 `true`。
- XY 是否先做 REP103 映射。
- Z 是否為安全且可達的 `0.05 m`。
- 座標是否超出手臂工作空間。

先執行 8 點 probe 區分「MoveIt 設定問題」與「相機座標問題」。

### 15.6 主控說 HOME 尚未成功

HOME worker 尚未結束時按 R，會顯示 motion already running 並以 busy 拒絕，不覆蓋 HOME worker；等待 HOME 完成後再操作。啟動時 PING/HOME 的 I/O、ERR 或 ACK 失敗，以及運動期間 CM530 失敗，都會立即嘗試 STOP、標記位置未知並拒絕 R。即使 STOP 有 ACK 也不能解鎖。先處理 serial、回覆或 torque 問題，再重新啟動主控並成功 HOME。

### 15.7 CM530 timeout

- 確認 57600、8N1、LF。
- 確認正式韌體已燒錄。
- 確認沒有其他程式占用。
- 確認 `READY` 之後能回 `PONG`。
- timeout 後立即停止後續 PT、嘗試 STOP、位置未知且鎖定 R。
- 排除原因後需重新啟動主控並 HOME，不能直接重按 R。

### 15.8 `ERR,RANGE`

AX position 超出 `0..1023`。ROS 應在發送前嚴格檢查每個點並拒絕超界值，禁止 clamp。若仍收到 ERR,RANGE，依 CM530 故障流程立即 STOP、位置未知並鎖定 R，檢查校正與傳送內容後重新啟動 HOME。

### 15.9 按 R 沒反應

- 主控必須在互動 terminal 啟動。
- Docker detached 啟動沒有可輸入的 stdin。
- 確認 terminal focus 在主控視窗。
- 可輸入大寫或小寫 R；line mode 時輸入 R 後按 Enter。

### 15.10 package 找不到

```bash
source /opt/ros/galactic/setup.bash
source /root/ws/install/setup.bash
ros2 pkg prefix ros2_main_control
```

若仍找不到，重新 colcon build。

### 15.11 RViz 不動或出現同步 warning

```bash
ros2 action list -t | grep /joint_trajectory_controller/follow_joint_trajectory
ros2 control list_controllers
ros2 topic echo /joint_states
```

- action 不存在：確認已使用 `fake.launch.py`，不是只啟動 `move_group.launch.py`。
- controller 不是 `active`：查看 launch terminal 的 controller spawner 錯誤。
- goal rejected 或 result error：確認主控 `joint_names` 與 controller 設定相同。
- 只想測實體手臂：加入 `-p rviz_sync_enabled:=false`。
- CM530 正常但 RViz warning：屬於預期的最佳努力降級，實體流程不會因此中止。

## 16. 實機校正建議

### 16.1 相機比例

在桌面放置已知長度標尺，量測兩點像素距離：

```text
scale_px_per_meter = pixel_distance / real_distance_meter
```

把結果傳給 OpenCV：

```bash
./start_pp.sh -p scale_px_per_meter:=<calibrated_value>
```

### 16.2 相機與手臂方向

在畫面中心前方放一個測試點，確認映射後 `base_x` 增加；在畫面左側放測試點，確認 `base_y` 增加。若方向不符，不要直接更改 AX sign，先修正相機到 base 的座標映射。

### 16.3 平移偏移

目前 service 原點是影像中心，程式尚未加入 camera center 到 arm base 的平移 offset。實機若鏡頭中心不在手臂 base 原點，必須新增或校正 `base_x/base_y` offset，否則 IK 有解但落點會整體偏移。

### 16.4 AX 中心與方向

每次只測一軸，小幅從 512 改到 520，記錄實際方向，再設定 `ax_signs`。不要同時修改四軸。

## 17. 安全限制

- 完整規劃與 fraction == 1 只表示 MoveIt 回傳的路徑完整，仍取決於模型、場景與實機校正；桌面碰撞模型未宣稱已校正，不能保證實體無碰撞。
- ik_avoid_collisions 預設 false；不要把 IK 成功當作碰撞檢查通過。
- CM530 韌體不變，dt_ms 仍被忽略；ROS 等累計時間到達才送 PT，ACK 過晚或等待晚喚醒均順延後續排程而不追趕、不壓縮後續點間隔，不保證實體速度。
- motion_dt_ms=300 僅用於 HOME 動畫；R 時間來自合併軌跡與必要的 Cartesian 補時。
- AX 轉換拒絕超界，不做 clamp；合法 AX 值仍不等於機械安全。
- HOME、PT、END 的 ACK 不證明馬達到位，沒有 present position feedback，不能承諾速度、跟隨精度或到位時間。
- 保存的規劃起點是命令狀態；RViz fake /joint_states 不是實體回授。
- RViz 同步失敗不影響 CM530；CM530 失敗則立即嘗試 STOP、位置未知、R 鎖定，需重啟 HOME。
- STOP 不保證實體立刻停止，不關 torque，不是硬體斷電急停；已送出的 RViz 動畫可能繼續。
- Ctrl+C 取消未送出點並執行 STOP 與 worker 清理後才關 serial；等待中的 serial I/O 可能直到回覆或 timeout 才返回。
- 沒有吸盤狀態或抓取確認；target 僅記錄，ESP32 不在本版範圍。
- 相機 Z 固定為零，z=0.02 m 是 end-effector link 相對 base 的座標；吸盤 TCP 未宣稱已校正，不是距桌面 2 cm 或即時測高結果。
- 正式 8/8 和 79 項測試均不等於實機驗證，未完成實機校正與驗收前不可視為可無人操作。

## 18. 後續整合順序

1. 保留正式 8/8、重新建置與 79 項單元測試證據，完成第 14.8 節尚待專項驗證項目。
2. 確認 serial 映射與 PING/HOME，完成小幅四軸校正。
3. 校正相機比例、camera 到 base 外參、桌面高度與碰撞模型、吸盤 TCP 及機械可動範圍。
4. 在現場監看下驗證完整接近與垂降，獨立觀察實際運動。
5. 後續另行加入位置回授、到位確認與復原策略。
6. ESP32 吸取、target 放置、返回接近高度或 HOME 為後續功能，不屬本次動作。

## 19. 快速檢查表

### 啟動前

- [ ] `mytest` 正在執行。
- [ ] container 看得到 CM530 serial device。
- [ ] RoboPlus 與手動 serial 工具已關閉。
- [ ] `/compute_ik`、`/plan_kinematic_path`、`/compute_cartesian_path` 均存在。
- [ ] `/joint_trajectory_controller/follow_joint_trajectory` 存在。
- [ ] `joint_trajectory_controller` 與 `joint_state_broadcaster` 都是 `active`。
- [ ] `/camera/get_object_point` 存在。
- [ ] 相機畫面可正確標出 current 與 target。
- [ ] 手臂周圍已清空。
- [ ] 實體斷電方式已準備。

### 主控啟動後

- [ ] 收到 `PONG`。
- [ ] 收到 `OK,HOME`。
- [ ] 日誌顯示 `Startup HOME sequence finished.`。
- [ ] RViz HOME 成功，或已確認 warning 不影響 CM530 HOME。
- [ ] raw 座標合理且 z 為 0。
- [ ] 已確認 Z 是 end-effector link 對 base 座標，現場桌面與 TCP 必須另行校正。
- [ ] 兩段完整規劃成功且 Cartesian fraction == 1。
- [ ] 全部點的 joint order、時間與嚴格 AX 檢查通過。
- [ ] R 未因 CM530 失敗而鎖定；故障後必須重新啟動 HOME。
- [ ] 理解目前命令狀態不是實際到位回授。
- [ ] 第一次動作有人看守硬體。

### 停止後

- [ ] 主控 terminal 已 `Ctrl+C`。
- [ ] 未送出點已取消，worker 已結束，STOP 已嘗試，未強制提前關閉 serial。
- [ ] serial port 已釋放。
- [ ] OpenCV 相機已釋放。
- [ ] MoveIt 已依需要停止。
- [ ] 不再使用 USB 時已 detach。

## 20. 重要來源

- 主控 README：`D:\畢業專題\ros2_main_control\README.md`
- CM530 正式規格：`D:\畢業專題\CM530\CM530_ROS_BRIDGE-main\15 cm530 test\ROS_CM530_INTERFACE_SPEC.txt`
- OpenCV service：`D:\畢業專題\OpenCV\OpenCV_ROS2_Bridge_test.01-main\opencv_ros2_bridge_interfaces\srv\GetObjectPoint.srv`
- OpenCV 啟動腳本：`D:\畢業專題\OpenCV\OpenCV_ROS2_Bridge_test.01-main\start_pp.sh`
- 正式完整 R 證據：`D:\畢業專題\ros2_main_control\test_results\multipoint_probe_final.json` 與同名 `.log`。
- PhantomX MoveIt：`D:\畢業專題\phantomx_pincher-ros2\phantomx_pincher-ros2\phantomx_pincher_moveit_config`
- [Microsoft：將 USB 裝置連接到 WSL](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)
- [Docker：使用 `--device` 加入 host device](https://docs.docker.com/reference/cli/docker/container/run/#add-host-device-to-container---device)
