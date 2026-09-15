# PhantomX Puzzle System

以 ROS 2 Humble 整合桌面拼圖辨識、MoveIt 多點取物軌跡、RViz 預期軌跡同步，以及 CM530/AX-12A 串列控制。本 repository 是部署入口，目標平台只有：

- Windows x86_64 + Docker Desktop/WSL2，容器架構 `linux/amd64`
- NVIDIA Jetson AGX Orin + Jetson Ubuntu，容器架構 `linux/arm64`

一般 Ubuntu x86_64 不是第三個驗收平台。

## Components

- `components/vision`: `ping152/puzzle-opencv-ros2`
- `components/cm530`: `ping152/phantomx-cm530-bridge`
- `components/controller`: `ping152/phantomx-puzzle-controller`
- `components/phantomx_pincher`: 固定的上游 PhantomX ROS 2 快照與 Humble 相容調整

版本與映像清單在 `repositories.lock.yaml`。正式發布後使用 workflow 產生的 `release.env`，映像必須是 `@sha256:` digest，不使用 `latest`。

## Quick Start

Windows PowerShell：

```powershell
git clone --recurse-submodules https://github.com/ping152/phantomx-puzzle-system.git
cd phantomx-puzzle-system
.\scripts\setup-windows.ps1
.\scripts\test-windows-sim.ps1
```

Jetson：

```bash
git clone --recurse-submodules https://github.com/ping152/phantomx-puzzle-system.git
cd phantomx-puzzle-system
./scripts/setup-jetson.sh
./scripts/test-jetson-sim.sh
```

模擬腳本不會開啟實體 serial，也不會驅動手臂。

## Hardware Safety

實機模式必須明確設定唯一 owner：

```powershell
$env:HARDWARE_OWNER = "windows"
.\scripts\start-windows-hardware.ps1
```

```bash
export HARDWARE_OWNER=jetson
./scripts/start-jetson-hardware.sh
```

未設定、設定錯誤、serial 被占用、相機不存在，或未在提示中輸入 `HOME`，腳本都會停止。兩台電腦不可同時連接並控制同一支手臂。

完整安裝、USB、DDS、RViz 與驗收流程請見 [Windows / Jetson 部署手冊](docs/DEPLOYMENT_WINDOWS_JETSON.md)。既有 `ROS2主控節點_完整操作手冊.*` 記錄 Galactic 開發與 79 項測試的歷史基準；正式部署以本文件與 Humble 手冊為準。

## Current Scope

按 `R` 會取得 `current_position`，規劃到物品上方並垂直下降到取物高度，把同一份多點關節軌跡送給 RViz 與 CM530。`target_position` 目前只讀取與顯示；吸盤、搬運與放置尚未納入本版本。

RViz 顯示命令目標，不是 AX-12A 的實際位置回授。實機前必須重新校正相機外參、桌面高度、AX center/sign 與工作範圍。

## License

本專案自行撰寫內容採 Apache-2.0。PhantomX、STM32 函式庫及其他第三方內容維持各自授權，詳見 `THIRD_PARTY_NOTICES.md` 與各 component 的授權檔。

