# RemoteCC

在 Apple Vision Pro 上遠端喚醒並連線到指定的 Mac（不限自己 Apple ID 登入的機器）。

流程：App 送出 **Wake-on-LAN** 喚醒封包 → 等待 Mac 開機/喚醒 → 透過 **VNC（螢幕共享）** 連線並顯示畫面，可用手勢點擊/拖曳操作、用系統鍵盤打字。

---

## 專案結構

```
RemoteCC/
  RemoteCC.xcodeproj/          Xcode 專案檔
  RemoteCC/
    RemoteCCApp.swift          App 進入點
    Models/SavedMac.swift      已儲存的 Mac 資料模型
    Services/
      WakeOnLAN.swift          發送 WoL magic packet
      KeychainStore.swift      VNC 密碼存到 Keychain（不進 iCloud、不上傳）
      MacStore.swift           已儲存 Mac 清單（存在 UserDefaults）
      VNCConnectionManager.swift  包裝 RoyalVNCKit 的 VNC 連線
    Views/
      MacListView.swift        主畫面：Mac 清單
      AddEditMacView.swift     新增/編輯一台 Mac
      RemoteScreenView.swift   喚醒 + 連線 + 顯示遠端畫面
```

VNC 協定實作用的是開源套件 **[RoyalVNCKit](https://github.com/royalapplications/royalvnc)**（官方支援 visionOS），透過 Swift Package Manager 自動下載，不需要額外手動安裝。

---

## 第一次使用：從零開始教你用 Xcode

### 1. 安裝 Xcode

在你的 **Mac** 上打開 App Store，搜尋「Xcode」，安裝（約 10GB+，需要一點時間）。第一次開啟 Xcode 會再跳出安裝額外元件的提示，按著裝完就好。

> 這一步只能在 Mac 上做，Xcode 沒有 Windows 版。

### 2. 打開這個專案

建議把這個 repo clone 到固定的本地資料夾，方便之後每次開發都在同一個地方，例如：

```bash
mkdir -p ~/Documents/Projects
cd ~/Documents/Projects
git clone https://github.com/cs90s203/remotecc.git RemoteCC
cd RemoteCC
git checkout claude/vision-pro-remote-connection-qwzk7c
```

（GitHub 帳密/SSH key 沒設過的話，用 HTTPS 網址 clone 時會跳出登入視窗，照著登入即可。之後每次都在 `~/Documents/Projects/RemoteCC` 這個資料夾裡 `git pull` 抓最新版本、`git push` 上傳你的修改。）

1. 在 Finder 找到 `RemoteCC.xcodeproj`（就在 `~/Documents/Projects/RemoteCC` 底下），**雙擊**打開（Xcode 會自動啟動）
2. Xcode 打開後，左側會看到專案的檔案樹（跟上面「專案結構」一樣）

### 3. 設定簽署（Signing）—— 這步一定要做

蘋果規定每個要安裝到實機的 App 都要「簽署」，用你的 Apple ID 就能簽（不用花錢的付費開發者帳號，個人使用足夠）：

1. 在左側點最上面的藍色專案圖示「RemoteCC」
2. 中間畫面選上方的「Signing & Capabilities」分頁
3. 「Team」下拉選單選擇你的 Apple ID（如果清單裡沒有，點 Xcode 選單 → Settings → Accounts，用 `+` 加入你的 Apple ID）
4. 如果「Bundle Identifier」顯示紅字衝突，把 `com.cs90s203.RemoteCC` 改成你自己的，例如 `com.你的名字.RemoteCC`

### 4. 等 Xcode 抓套件依賴

打開專案時 Xcode 會自動去抓 RoyalVNCKit（左下角會看到進度轉圈），第一次可能要等 1-2 分鐘，抓完才能編譯。如果卡住，選單 File → Packages → Reset Package Caches 再試一次。

### 5. 選執行目標並執行

上方工具列，Xcode 的「執行目標」下拉選單（通常寫著裝置名稱）：

- **沒有 Vision Pro 在身邊**：選「Apple Vision Pro」模擬器（Simulator）先測（VNC 畫面在模擬器裡可以正常顯示，但 Wake-on-LAN 因為模擬器沒有真實網路介面卡，喚醒功能無法在模擬器完整測試）
- **要裝到真的 Vision Pro**：用傳輸線把 Vision Pro 接到 Mac，或用同一個 Wi-Fi 做「無線偵錯」，這個裝置名稱就會出現在下拉選單裡

選好後按左上角的 ▶️（或按 `Cmd + R`）執行。

### 6. 真機第一次執行會遇到的提示

- Vision Pro 上會問「是否信任這台電腦」→ 選信任
- 第一次執行 App 可能顯示「未受信任的開發者」→ 到 Vision Pro 的「設定 > 一般 > VPN 與裝置管理」，找到你的 Apple ID，點「信任」

---

## App 內使用方式

1. 打開 App，右上角「+」新增一台 Mac：
   - **顯示名稱**：隨便取
   - **IP 或主機名稱**：目標 Mac 的區網 IP（在該 Mac 的「系統設定 > Wi-Fi > 詳細資訊」可以看到，建議設定固定 IP 避免常常變動）
   - **MAC 位址**：同樣在「系統設定 > 網路 > Wi-Fi/乙太網路 > 詳細資訊」查得到，格式 `AA:BB:CC:DD:EE:FF`
   - **使用者名稱 / 密碼**：目標 Mac 的登入帳密（螢幕共享登入用，不需要跟你的 Apple ID 一樣）
2. 目標 Mac 需要先打開：**系統設定 > 一般 > 共享 > 螢幕共享**（打開後 VNC 連線才會接受）
3. 目標 Mac 需要打開：**系統設定 > 電池/節能 > 選項 > 網路存取時喚醒**，並確保有插電（合蓋深度睡眠 + 沒插電時，Wake-on-LAN 不一定能喚醒，這是硬體限制）
4. 點清單裡的 Mac，App 會自動：送出喚醒封包 → 等待幾秒 → 嘗試 VNC 連線 → 顯示畫面
5. 畫面上：單點＝滑鼠點擊，拖曳＝滑鼠拖曳，右上角鍵盤圖示可叫出系統鍵盤打字傳送到遠端

---

## 已知限制 / 老實說的部分

- **這是我在雲端環境寫的專案，沒有 Xcode 可以實際編譯測試**，所以第一次在你的 Mac 上 build 時有機率會遇到一兩個小編譯錯誤，最可能出錯的地方是 `Services/VNCConnectionManager.swift`（我在檔案開頭寫了註解說明），因為它呼叫的是第三方套件 RoyalVNCKit 的 API，套件版本更新可能讓個別方法名稱有些微差異。如果編譯報錯，把錯誤訊息貼給我，我可以直接幫你改。
- Wake-on-LAN 只能喚醒**同一個區域網路**內、且**插著電源**的 Mac；跨網路（例如你人在外面、Mac 在家）需要路由器支援 WoL 轉發或額外架設，這個版本還沒做。
- 目前沒有做剪貼簿同步、螢幕旋轉自適應等進階功能，先求「能喚醒、能連上、能操作」堪用。

---

## Deploy / 之後的開發

這是原生 visionOS App，跟 `jp-learning-app` 的網頁 PWA 不一樣，**沒有 `deploy.sh` 這種東西**——更新方式是改完程式碼後在 Xcode 按 ▶️ 重新安裝到 Vision Pro，或之後上架 TestFlight/App Store 才需要额外流程。
