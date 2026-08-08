# CHANGELOG

## 0.1.0 — 初版

- 新增 visionOS App 專案骨架（`RemoteCC.xcodeproj`）
- Wake-on-LAN：`Services/WakeOnLAN.swift`，透過 UDP broadcast 送出 magic packet
- Mac 清單管理：`Services/MacStore.swift`（UserDefaults）+ `Services/KeychainStore.swift`（VNC 密碼存 Keychain）
- VNC 螢幕共享連線：`Services/VNCConnectionManager.swift`，整合開源套件 [RoyalVNCKit](https://github.com/royalapplications/royalvnc)（SPM 依賴，官方支援 visionOS）
- UI：`MacListView`（清單/新增/編輯/刪除）、`AddEditMacView`（表單）、`RemoteScreenView`（喚醒 → 連線 → 畫面顯示 → 點擊/拖曳/打字操作）
- 支援連線任何有開啟「螢幕共享」的 Mac，不限自己 Apple ID 登入的機器
- README 補上完整 Xcode 新手教學（安裝、簽署、抓套件、選裝置、執行、真機信任開發者）
- README 補上建議的本地 clone 路徑（`~/Documents/Projects/RemoteCC`）與 git clone/checkout 指令
