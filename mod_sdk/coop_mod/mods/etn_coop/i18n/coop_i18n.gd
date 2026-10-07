extends RefCounted

## mod 独立本地化：运行时构建 zh_CN/en/pt/vi_VN 四语 coop_* 翻译并注册到 TranslationServer。
## 无需修改本体 CSV，也不依赖导入管线。

const LOCALES: Array[String] = ["zh_CN", "en", "pt", "vi_VN"]

const MESSAGES: Dictionary = {
	"coop_title": {"zh_CN": "联机", "en": "CO-OP", "pt": "CO-OP", "vi_VN": "CO-OP"},
	"coop_mode_lan": {"zh_CN": "局域网", "en": "LAN", "pt": "LAN", "vi_VN": "LAN"},
	"coop_mode_relay": {"zh_CN": "中继", "en": "RELAY", "pt": "RELAY", "vi_VN": "RELAY"},
	"coop_mode_dedicated": {"zh_CN": "专用", "en": "DEDICATED", "pt": "DEDICADO", "vi_VN": "RIÊNG"},
	"coop_mode_subtitle_lan": {"zh_CN": "同一局域网内联机", "en": "Co-op on the same LAN", "pt": "Co-op na mesma LAN", "vi_VN": "Chơi chung cùng LAN"},
	"coop_mode_subtitle_relay": {"zh_CN": "跨网络中继联机（WebSocket）", "en": "Relay co-op over WebSocket", "pt": "Co-op via relay WebSocket", "vi_VN": "Chơi chung qua relay WebSocket"},
	"coop_mode_subtitle_dedicated": {"zh_CN": "专用服务器（暂不可用）", "en": "Dedicated server (unavailable)", "pt": "Servidor dedicado (indisponível)", "vi_VN": "Máy chủ riêng (không khả dụng)"},
	"coop_host": {"zh_CN": "开服", "en": "HOST", "pt": "HOSPEDAR", "vi_VN": "TẠO PHÒNG"},
	"coop_join": {"zh_CN": "加入", "en": "JOIN", "pt": "ENTRAR", "vi_VN": "THAM GIA"},
	"coop_host_lan_ip_placeholder": {"zh_CN": "主机局域网 IP", "en": "Host LAN IP", "pt": "IP da LAN do host", "vi_VN": "IP LAN của chủ phòng"},
	"coop_lan_note": {"zh_CN": "同一局域网内可直接连接。", "en": "Connect directly within the same LAN.", "pt": "Conecte-se diretamente na mesma LAN.", "vi_VN": "Kết nối trực tiếp trong cùng LAN."},
	# LAN 房间发现
	"coop_lan_scanning": {"zh_CN": "正在扫描局域网…", "en": "Scanning LAN...", "pt": "Procurando na LAN...", "vi_VN": "Đang quét LAN..."},
	"coop_lan_rooms": {"zh_CN": "局域网房间", "en": "LAN rooms", "pt": "Salas LAN", "vi_VN": "Phòng LAN"},
	"coop_lan_no_rooms": {"zh_CN": "未发现房间", "en": "No rooms found", "pt": "Nenhuma sala encontrada", "vi_VN": "Không tìm thấy phòng"},
	# 版本/协议握手
	"coop_version_mismatch": {"zh_CN": "版本不一致，无法联机", "en": "Version mismatch, cannot join", "pt": "Versão incompatível", "vi_VN": "Phiên bản không khớp"},
	# 实时战绩面板
	"coop_sb_title": {"zh_CN": "战绩", "en": "SCOREBOARD", "pt": "PLACAR", "vi_VN": "BẢNG ĐIỂM"},
	"coop_sb_player": {"zh_CN": "玩家", "en": "Player", "pt": "Jogador", "vi_VN": "Người chơi"},
	"coop_sb_kills": {"zh_CN": "击杀", "en": "Kills", "pt": "Abates", "vi_VN": "Hạ gục"},
	"coop_sb_damage": {"zh_CN": "伤害", "en": "Damage", "pt": "Dano", "vi_VN": "Sát thương"},
	"coop_sb_coins": {"zh_CN": "金币", "en": "Coins", "pt": "Moedas", "vi_VN": "Xu"},
	# OPTION 页：调试窗口
	"coop_option_debug_hud": {"zh_CN": "调试窗口", "en": "Debug HUD", "pt": "HUD de depuração", "vi_VN": "Bảng gỡ lỗi"},
	"coop_on": {"zh_CN": "开", "en": "ON", "pt": "LIG", "vi_VN": "BẬT"},
	"coop_off": {"zh_CN": "关", "en": "OFF", "pt": "DES", "vi_VN": "TẮT"},
	"coop_saki_server": {"zh_CN": "使用 Saki 服务器", "en": "Use Saki server", "pt": "Usar servidor Saki", "vi_VN": "Dùng máy chủ Saki"},
	"coop_relay_server_placeholder": {"zh_CN": "中继服务器地址", "en": "Relay server address", "pt": "Endereço do servidor relay", "vi_VN": "Địa chỉ máy chủ relay"},
	"coop_create_room": {"zh_CN": "创建房间", "en": "CREATE ROOM", "pt": "CRIAR SALA", "vi_VN": "TẠO PHÒNG"},
	"coop_room_code_empty": {"zh_CN": "房间号：-", "en": "Room: -", "pt": "Sala: -", "vi_VN": "Phòng: -"},
	"coop_room_code_creating": {"zh_CN": "正在创建房间…", "en": "Creating room...", "pt": "Criando sala...", "vi_VN": "Đang tạo phòng..."},
	"coop_room_code_value": {"zh_CN": "房间号：%s", "en": "Room: %s", "pt": "Sala: %s", "vi_VN": "Phòng: %s"},
	"coop_room_code_placeholder": {"zh_CN": "房间号", "en": "Room code", "pt": "Código da sala", "vi_VN": "Mã phòng"},
	"coop_join_room": {"zh_CN": "加入房间", "en": "JOIN ROOM", "pt": "ENTRAR NA SALA", "vi_VN": "VÀO PHÒNG"},
	"coop_relay_note": {"zh_CN": "跨网络需自建中继服务器。", "en": "Cross-network needs a relay server.", "pt": "Rede externa requer servidor relay.", "vi_VN": "Khác mạng cần máy chủ relay."},
	"coop_dedicated_note": {"zh_CN": "专用服务器模式暂不可用。", "en": "Dedicated server mode is not available.", "pt": "Modo servidor dedicado indisponível.", "vi_VN": "Chế độ máy chủ riêng không khả dụng."},
	"coop_start_run": {"zh_CN": "开始游戏", "en": "START RUN", "pt": "INICIAR", "vi_VN": "BẮT ĐẦU"},
	"coop_test_room": {"zh_CN": "测试房", "en": "TEST ROOM", "pt": "SALA DE TESTE", "vi_VN": "PHÒNG TEST"},
	"coop_return_hint": {"zh_CN": "返回", "en": "Return", "pt": "Voltar", "vi_VN": "Quay lại"},
	"coop_unavailable": {"zh_CN": "不可用", "en": "unavailable", "pt": "indisponível", "vi_VN": "không khả dụng"},
	"coop_your_ip_format": {"zh_CN": "你的 IP：%s", "en": "Your IP: %s", "pt": "Seu IP: %s", "vi_VN": "IP của bạn: %s"},
	"coop_status_format": {"zh_CN": "%s · %s", "en": "%s · %s", "pt": "%s · %s", "vi_VN": "%s · %s"},
	"coop_status_offline": {"zh_CN": "离线", "en": "offline", "pt": "offline", "vi_VN": "ngoại tuyến"},
	"coop_status_relay_not_implemented": {"zh_CN": "中继联机尚未实现", "en": "relay networking is not implemented yet", "pt": "rede relay ainda não implementada", "vi_VN": "mạng relay chưa được triển khai"},
	"coop_status_dedicated_unavailable": {"zh_CN": "专用服务器模式不可用", "en": "dedicated server mode is not available", "pt": "modo servidor dedicado indisponível", "vi_VN": "chế độ máy chủ riêng không khả dụng"},
	"coop_status_host_failed": {"zh_CN": "开服失败", "en": "Host failed", "pt": "Falha ao hospedar", "vi_VN": "Tạo phòng thất bại"},
	"coop_status_join_failed": {"zh_CN": "加入失败", "en": "Join failed", "pt": "Falha ao entrar", "vi_VN": "Tham gia thất bại"},
	"coop_status_enter_host_ip": {"zh_CN": "加入失败：请输入主机局域网 IP", "en": "Join failed: enter host LAN IP", "pt": "Falha: informe o IP da LAN do host", "vi_VN": "Thất bại: nhập IP LAN của chủ phòng"},
	"coop_status_invalid_host_ip": {"zh_CN": "加入失败：请用主机局域网 IP，而非 0.0.0.0", "en": "Join failed: use host LAN IP, not 0.0.0.0", "pt": "Falha: use o IP da LAN, não 0.0.0.0", "vi_VN": "Thất bại: dùng IP LAN, không phải 0.0.0.0"},
	"coop_status_relay_failed": {"zh_CN": "中继失败", "en": "Relay failed", "pt": "Falha no relay", "vi_VN": "Relay thất bại"},
	"coop_status_relay_room_code_empty": {"zh_CN": "中继失败：房间号为空", "en": "Relay failed: room code is empty", "pt": "Relay falhou: código da sala vazio", "vi_VN": "Relay thất bại: mã phòng trống"},
	"coop_status_creating_relay_room": {"zh_CN": "正在创建中继房间", "en": "Creating relay room", "pt": "Criando sala relay", "vi_VN": "Đang tạo phòng relay"},
	"coop_status_only_host_start": {"zh_CN": "只有主机能开始联机", "en": "Only host can start a LAN run", "pt": "Só o host pode iniciar", "vi_VN": "Chỉ chủ phòng mới bắt đầu"},
	"coop_status_waiting_for_players": {"zh_CN": "等待所有玩家选择", "en": "Waiting for all players to select", "pt": "Aguardando todos escolherem", "vi_VN": "Đang chờ mọi người chọn"},
	"coop_status_connected_relay": {"zh_CN": "已连接中继", "en": "Connected to relay", "pt": "Conectado ao relay", "vi_VN": "Đã kết nối relay"},
	"coop_status_connected_host": {"zh_CN": "已连接主机", "en": "Connected to host", "pt": "Conectado ao host", "vi_VN": "Đã kết nối chủ phòng"},
	"coop_status_relay_connection_failed": {"zh_CN": "中继连接失败", "en": "Relay connection failed", "pt": "Falha na conexão do relay", "vi_VN": "Kết nối relay thất bại"},
	"coop_status_connection_failed": {"zh_CN": "连接失败", "en": "Connection failed", "pt": "Falha na conexão", "vi_VN": "Kết nối thất bại"},
	"coop_status_relay_disconnected": {"zh_CN": "中继已断开", "en": "Relay disconnected", "pt": "Relay desconectado", "vi_VN": "Relay đã ngắt"},
	"coop_status_server_disconnected": {"zh_CN": "与主机断开", "en": "Server disconnected", "pt": "Servidor desconectado", "vi_VN": "Máy chủ đã ngắt"},
	# 房主离开（LAN/Relay）：客户端提示后过场回主菜单
	"coop_host_left": {"zh_CN": "房主已离开，房间已关闭", "en": "Host left. Room closed.", "pt": "O anfitrião saiu. Sala fechada.", "vi_VN": "Chủ phòng đã rời. Phòng đã đóng."},
	"coop_status_relay_room_created": {"zh_CN": "中继房间 %s 已创建", "en": "Relay room %s created", "pt": "Sala relay %s criada", "vi_VN": "Đã tạo phòng relay %s"},
	"coop_status_selected_players": {"zh_CN": "已选择 %s 名玩家", "en": "Selected %s players", "pt": "%s jogadores selecionados", "vi_VN": "Đã chọn %s người chơi"},
	"coop_status_peer_joined": {"zh_CN": "玩家 %s 已加入", "en": "Peer %s joined", "pt": "Par %s entrou", "vi_VN": "Người %s đã vào"},
	"coop_status_peer_left": {"zh_CN": "玩家 %s 已离开", "en": "Peer %s left", "pt": "Par %s saiu", "vi_VN": "Người %s đã rời"},
	"coop_status_host_failed_detail": {"zh_CN": "开服失败：%s", "en": "Host failed: %s", "pt": "Falha ao hospedar: %s", "vi_VN": "Tạo phòng thất bại: %s"},
	"coop_status_join_failed_detail": {"zh_CN": "加入失败：%s", "en": "Join failed: %s", "pt": "Falha ao entrar: %s", "vi_VN": "Tham gia thất bại: %s"},
	"coop_status_hosting_lan_port": {"zh_CN": "局域网开服端口 %s", "en": "Hosting LAN on port %s", "pt": "Hospedando LAN na porta %s", "vi_VN": "Tạo LAN cổng %s"},
	"coop_status_hosting_address": {"zh_CN": "开服 %s", "en": "Hosting %s", "pt": "Hospedando %s", "vi_VN": "Tạo phòng %s"},
	"coop_status_joining_relay_room": {"zh_CN": "正在加入中继房间 %s", "en": "Joining relay room %s", "pt": "Entrando na sala relay %s", "vi_VN": "Đang vào phòng relay %s"},
	"coop_status_joining_address": {"zh_CN": "正在加入 %s", "en": "Joining %s", "pt": "Entrando em %s", "vi_VN": "Đang vào %s"},
	"coop_status_joined_relay_peer": {"zh_CN": "已作为 %s 加入中继", "en": "Joined relay as peer %s", "pt": "Entrou no relay como par %s", "vi_VN": "Đã vào relay với mã %s"},
	"coop_status_relay_failed_detail": {"zh_CN": "中继失败：%s", "en": "Relay failed: %s", "pt": "Falha no relay: %s", "vi_VN": "Relay thất bại: %s"},
	# 倒地/救援（本体 player.gd 引用）
	"lan_player_down": {"zh_CN": "倒地！", "en": "DOWN!", "pt": "CAÍDO!", "vi_VN": "GỤC!"},
	"lan_player_revived": {"zh_CN": "复起！", "en": "REVIVED!", "pt": "REVIVIDO!", "vi_VN": "HỒI SINH!"},
	"lan_rescue_prompt": {"zh_CN": "救援", "en": "RESCUE", "pt": "RESGATAR", "vi_VN": "CỨU"},
	# 倒地队友头顶求助（四语一致，保持需求字样）
	"coop_help": {"zh_CN": "HELP!", "en": "HELP!", "pt": "HELP!", "vi_VN": "HELP!"},
	# 选项页：其它联机玩家攻击反馈频率
	"coop_mode_option": {"zh_CN": "选项", "en": "OPTION", "pt": "OPÇÕES", "vi_VN": "TÙY CHỌN"},
	"coop_mode_subtitle_option": {"zh_CN": "其它联机玩家攻击反馈频率", "en": "Other players' attack feedback frequency", "pt": "Frequência de feedback dos outros jogadores", "vi_VN": "Tần suất phản hồi đòn của người khác"},
	"coop_option_remote_effect": {"zh_CN": "其它玩家特效", "en": "Others' effects", "pt": "Efeitos dos outros", "vi_VN": "Hiệu ứng người khác"},
	"coop_option_remote_flash": {"zh_CN": "其它玩家闪白", "en": "Others' hit flash", "pt": "Flash dos outros", "vi_VN": "Chớp trắng người khác"},
	"coop_option_remote_text": {"zh_CN": "其它玩家飘字", "en": "Others' damage text", "pt": "Texto de dano dos outros", "vi_VN": "Số sát thương người khác"},
	"coop_option_note": {"zh_CN": "仅影响其它联机玩家造成的特效/闪白/飘字；本地玩家与敌人不受影响。", "en": "Only other players' effects / hit flash / damage text. Local player and enemies are unaffected.", "pt": "Só efeitos/flash/texto de outros jogadores.", "vi_VN": "Chỉ ảnh hưởng hiệu ứng của người chơi khác."},
	# 选项页：玩家 ID
	"coop_option_player_id": {"zh_CN": "玩家 ID", "en": "Player ID", "pt": "ID do jogador", "vi_VN": "ID người chơi"},
	"coop_option_player_id_placeholder": {"zh_CN": "输入你的名字", "en": "Enter your name", "pt": "Digite seu nome", "vi_VN": "Nhập tên của bạn"},
	"coop_player_id_saved": {"zh_CN": "已保存", "en": "Saved", "pt": "Salvo", "vi_VN": "Đã lưu"},
	"coop_player_id_too_long": {"zh_CN": "不可输入超过12字符", "en": "Cannot exceed 12 characters", "pt": "Não pode exceder 12 caracteres", "vi_VN": "Không được vượt quá 12 ký tự"},
	# 准备房 / 选人 / 就绪 / 难度
	"coop_start_game": {"zh_CN": "开始游戏", "en": "START GAME", "pt": "INICIAR JOGO", "vi_VN": "BẮT ĐẦU GAME"},
	"coop_only_host_interact": {"zh_CN": "只有房主能够互动", "en": "Only the host can interact", "pt": "Só o anfitrião pode interagir", "vi_VN": "Chỉ chủ phòng mới tương tác được"},
	"coop_ready": {"zh_CN": "已就绪", "en": "READY", "pt": "PRONTO", "vi_VN": "SẴN SÀNG"},
	"coop_waiting_host": {"zh_CN": "等待房主选择", "en": "Waiting for host", "pt": "Aguardando o anfitrião", "vi_VN": "Đang chờ chủ phòng"},
	"coop_wait_all_ready": {"zh_CN": "等待所有人就绪", "en": "Waiting for all players", "pt": "Aguardando todos os jogadores", "vi_VN": "Đang chờ mọi người sẵn sàng"},
	"coop_room_number": {"zh_CN": "房间号", "en": "Room", "pt": "Sala", "vi_VN": "Phòng"},
	"coop_room_ip": {"zh_CN": "IP", "en": "IP", "pt": "IP", "vi_VN": "IP"},
	"coop_select_support": {"zh_CN": "支援角色选择", "en": "Support selection", "pt": "Seleção de apoio", "vi_VN": "Chọn nhân vật hỗ trợ"},
	"coop_support_empty": {"zh_CN": "空", "en": "None", "pt": "Nenhum", "vi_VN": "Không"},
	"coop_difficulty": {"zh_CN": "难度选择", "en": "Difficulty", "pt": "Dificuldade", "vi_VN": "Độ khó"},
	"coop_cancel_ready_hint": {"zh_CN": "按 ESC 取消就绪", "en": "Press ESC to cancel ready", "pt": "Pressione ESC para cancelar", "vi_VN": "Nhấn ESC để hủy sẵn sàng"},
	"coop_select_character_hint": {"zh_CN": "选择角色以确认", "en": "Pick a character to confirm", "pt": "Escolha um personagem", "vi_VN": "Chọn nhân vật để xác nhận"},
	# 大厅准备（开始球）
	"coop_prepared": {"zh_CN": "已准备", "en": "READY", "pt": "PRONTO", "vi_VN": "SẴN SÀNG"},
	"coop_players_not_ready": {"zh_CN": "需要所有玩家准备", "en": "All players must be ready", "pt": "Todos precisam estar prontos", "vi_VN": "Cần tất cả người chơi sẵn sàng"},
	# 聊天室
	"coop_chat_title": {"zh_CN": "聊天", "en": "CHAT", "pt": "BATE-PAPO", "vi_VN": "TRÒ CHUYỆN"},
	"coop_chat_placeholder": {"zh_CN": "输入消息…", "en": "Type a message...", "pt": "Digite uma mensagem...", "vi_VN": "Nhập tin nhắn..."},
}


static func install() -> void:
	for loc in LOCALES:
		var t := Translation.new()
		t.locale = loc
		for key in MESSAGES.keys():
			var entry: Dictionary = MESSAGES[key]
			var text: String = str(entry.get(loc, entry.get("en", "")))
			t.add_message(StringName(key), StringName(text))
		TranslationServer.add_translation(t)
