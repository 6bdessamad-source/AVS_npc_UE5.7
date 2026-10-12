# AVS Build & Stream Manager v2 — Unreal Engine 5.7

Double-click **AVS_BUILD_MANAGER.bat** on the gaming rig. Keep the entire extracted kit together. Windows PowerShell 5.1, Windows 10/11, UE 5.7, and a GPU supporting hardware video encoding are required. The manager runs without administrator privileges; installers or a Windows firewall prompt may request them.

## First setup on the rig

1. Extract this ZIP, for example to `C:\AVS_Manager`. Open **AVS_BUILD_MANAGER.bat**.
2. Your uploaded project path, engine path, output directory, and release versions are preserved in the included config. Verify them in **BUILD / PATCH**.
3. In Unreal, enable **Pixel Streaming 2**, save, restart Unreal, and close the editor before building. An existing project using the original Pixel Streaming plugin can keep it; avoid enabling both unintentionally.
4. If your current packaged game did not include a Pixel Streaming plugin, create a **new Base release** with a distinct new baseline version (for example `AMV_STREAM_V1`). A content-only patch ZIP cannot add missing plugin binaries to an old installed game. Keep the new project's `Releases` baseline for future patches.
5. Run **INSTALL_PREREQUISITES.bat** once. It installs Node.js LTS and cloudflared through winget. Reopen the manager afterwards so it sees the new PATH. cloudflared is optional for LAN-only use; Node.js 22+ is required for signalling.
6. Open **START / STREAM**. Select the complete packaged game's actual EXE inside its `Binaries\Win64` folder, usually `AMV_VILLA_UE-Win64-Shipping.exe`. If you select the root launcher, the manager resolves the corresponding Shipping EXE where possible. Keep the complete package and any installed cumulative patches beside it.
7. The **Infrastructure folder** defaults to the included `PixelStreamingInfrastructure-UE5.7`. Click **SETUP STREAMING** once. Wait for the console to say setup completed; internet access is needed for npm dependencies. The setup checks each dependency/build command and uses your supplied UE5.7 source.
8. Click **START STREAM**. This starts the signalling server, waits for its ports, then starts the game offscreen with audio and the correct local signalling URL. Initial large-map loading can take longer than the registration check. Use **CHECK STATUS** afterwards.

## Use the laptop on the same network

After starting streaming, open the LAN URL printed in the console or saved in **AVS_PLAYER_LINKS.txt**, for example `http://192.168.1.25:8080/player.html`, on the laptop. Set **Rig LAN IP** explicitly if automatic detection selects a VPN or virtual adapter. The rig and laptop need network access to each other. Allow Node and your packaged game through Windows Firewall on your trusted private network when Windows asks. No router port forwarding is required for LAN use.

The GitHub page also accepts this local address. Because GitHub Pages uses HTTPS, it provides an **Open in tab** link for an HTTP LAN player instead of loading blocked mixed content in an iframe. This is intentional. A VPN linking both machines can use the same direct player path.

## Use the laptop over the internet

1. Keep the managed stream running, then click **CREATE INTERNET LINK**.
2. The manager starts a temporary cloudflared HTTPS tunnel for the player and signalling endpoint. No account or domain is required for a Quick Tunnel. Its address changes when the tunnel is restarted.
3. Open the complete **Laptop link** from **AVS_PLAYER_LINKS.txt** on your laptop. It opens the GitHub page with your rig address already filled in. The website embeds Epic's UE5.7 player; click its playback prompt if needed.
4. **Important for actual video:** HTTPS/WebSocket signalling and WebRTC media are separate. The tunnel does not relay the game's WebRTC media. STUN alone can work between some networks; other NAT/firewall combinations need a **TURN relay**. Enter a real TURN URL, username, and password supplied by your relay service, then stop and restart the managed stream. Example URL format: `turns:relay.example.com:5349?transport=tcp`. Credentials and server availability are yours to configure; no shared or fictitious relay is bundled.
5. For a permanent address, configure your own HTTPS reverse proxy, named tunnel, or suitable VPN HTTPS endpoint, and enter its root URL in **HTTPS player URL**. The public endpoint must serve Epic's player and support the signalling WebSocket. Your external proxy/tunnel remains yours to manage; STOP SESSION only closes the tunnel launched by this kit.

Anyone with an unrestricted temporary tunnel link can access your running game. Use it for your personal test session, and close it with **STOP SESSION** afterwards. For longer-term access, use your own access-controlled endpoint or private VPN. Cloudflare Quick Tunnels are intended for testing rather than production hosting.

## GitHub website

Source: `https://github.com/6bdessamad-source/AVS_npc_UE5.7/tree/main/avs-player`

Intended player URL after Pages is enabled and deployed:
`https://6bdessamad-source.github.io/AVS_npc_UE5.7/avs-player/`

One-time activation: repository **Settings → Pages → Source → GitHub Actions**. Then open **Actions → Publish AVS Player → Run workflow** if the initial upload's run already failed before Pages was enabled. The connected file-editing tools cannot change this repository administration setting. After activation the included workflow publishes website changes automatically. Wait for a successful deployment before using the intended URL.

The player page and build manager source are stored in isolated folders. The existing NPC plugin ZIP is preserved. GitHub hosts the webpage; your rig hosts the game and player/signalling runtime. This website cannot power on the rig, remotely launch arbitrary commands, or run the Unreal executable on GitHub.

## Buttons and commands

| Button | Effect |
| --- | --- |
| BUILD BASE RELEASE / BUILD PATCH | Existing Shipping BuildCookRun workflow, saved versions, live log, timestamped output, optional ZIP |
| START GAME | Launches the selected package locally in a window |
| SETUP STREAMING | Installs the selected Node workspaces and compiles the UE5.7 server/player |
| START STREAM | Starts signalling and the managed offscreen game |
| CREATE INTERNET LINK | Creates a temporary HTTPS endpoint, or uses your configured HTTPS address |
| CHECK STATUS | Checks managed processes and asks the signalling server for registered streamers |
| OPEN PLAYER | Opens the current HTTPS/GitHub player link, or the rig-local player |
| STOP SESSION | Stops only the recorded managed tunnel, game, and signalling process trees |

Use `AVS_START_GAME.bat`, `AVS_START_STREAM.bat`, `AVS_INTERNET_LINK.bat`, and `AVS_STOP_STREAM.bat` for equivalent command shortcuts. Save your settings by closing the manager or clicking an action first. The CLI is `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AVS_STREAM.ps1 -Action StartStream` (actions: Setup, StartGame, StartStream, Internet, Stop, OpenPlayer, Status). `AVS_BUILD_PATCH.BAT` now uses the manager's saved config instead of the original hardcoded paths.

Settings changes apply to the next session; stop before changing ports, resolution, game, or relay settings. Closing the manager leaves the managed session running. Reopen it and use STOP SESSION to stop it. Only one player is permitted per streamer by the generated server configuration.

## Troubleshooting

- **Empty `streamerList`**: A running server is not a registered game. Wait for map loading, check the selected EXE, verify the plugin was packaged, and check game logs. The manager passes `-PixelStreamingURL=ws://127.0.0.1:8888` (or your configured streamer port).
- **Game exits**: Check the complete package, prerequisites, and hardware encoding support. Keep project content and DLLs in the original packaged layout. See the game's `Saved\Logs` where available; Shipping logging depends on your project build settings.
- **Player opens but no video on the internet**: Verify a streamer appears, then check TURN, outbound network rules, and whether your relay credentials expired. Test LAN first to separate game problems from network traversal.
- **Port already used**: Stop your previous signalling console or choose distinct player/streamer ports. Default ports are 8080 and 8888; 8889 is reserved for SFU. Don't change ports during a live session.
- **Embedded player is blank or asks for sign-in**: Use **Open in tab**. Some authentication policies and frame protections require the direct player.
- **No cloudflared address appears**: Read `StreamingLogs/Tunnel-*.stderr.log`; check internet access and existing cloudflared configuration. You can use a configured HTTPS address instead.

TURN passwords in the saved manager config are encrypted for your current Windows user with DPAPI. Re-enter them if you move the kit to another account or PC. The generated runtime peer-options file necessarily contains the TURN credential for the server; it is local and removed when you stop. Don't upload your live config, `.runtime`, logs, player links, or packaged Unreal project to a public repository. The GitHub source uses a blank config example.

## Verification and limits

PowerShell scripts parse successfully with PowerShell 7.4 and with a separate syntax parser. Shared helpers were executed to test argument quoting (including spaces, quotes, and trailing backslashes), invalid settings, and BOM-free JSON. All seven selected Epic dependency/build steps compiled successfully. Player logic checks cover HTTPS embedding, direct LAN links, invalid URLs, auto-connect share links, and disconnect behavior. A live local signalling integration check verifies player assets and empty/populated streamer lists, including the PowerShell registration probe.

The Windows GUI, Unreal packaging, hardware video/audio encoding, and your rig-to-laptop network cannot be exercised on this Linux workspace. First real use still requires the setup above; no end-to-end game stream is claimed from these source/runtime checks. Browser visual QA was unavailable in this session.

Epic infrastructure provenance: your uploaded `PixelStreamingInfrastructure-UE5.7.zip`, archive revision `b6c32102848ffe8722965386822646a43d99d569`. Its license and notices are included. The original build runner is preserved byte-for-byte; new functionality is in the manager and streaming helper.

References: [Epic UE5.7 Pixel Streaming reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-pixel-streaming-reference?application_version=5.7), [Pixel Streaming 2 overview](https://dev.epicgames.com/documentation/unreal-engine/pixel-streaming-2-overview-in-unreal-engine?application_version=5.7), [GitHub Pages setup](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/), [TURN](https://developers.cloudflare.com/realtime/turn/what-is-turn/).
