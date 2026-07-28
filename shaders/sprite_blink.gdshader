shader_type canvas_item;

// 瞬移进度（0=正常，1=完全消失成线条）
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 线条密度（数值越大，线条越密集）
uniform float line_density : hint_range(4.0, 32.0) = 12.0;
// 线条粗细（0.1=细线，0.8=粗线）
uniform float line_thickness : hint_range(0.1, 0.9) = 0.4;
// 线条扭曲强度（水平摆动幅度）
uniform float warp_strength : hint_range(0.0, 0.2) = 0.08;
// 残影拖尾长度
uniform float trail_length : hint_range(0.0, 0.5) = 0.25;
// 线条发光强度
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.6;

void fragment() {
    vec2 uv = UV;
    float y = uv.y;

    // === 1. 计算当前像素属于哪条"动画线" ===
    // 每条线对应一个固定的Y位置区间
    float line_index = floor(y * line_density);
    float line_y = (line_index + 0.5) / line_density; // 线条中心Y坐标

    // 当前像素到线条中心的距离
    float dist_to_line = abs(y - line_y);
    // 线条的半宽（厚度）
    float half_thickness = (line_thickness / line_density) * 0.5;

    // === 2. 根据进度决定线条的激活状态 ===
    // 线条从底部向顶部逐条激活消失（动画感）
    float line_progress = line_index / line_density;
    // 激活阈值：低于进度的线条才开始变形
    float active_threshold = 1.0 - progress;

    // 线条的活跃程度（0=未激活，1=完全激活变形）
    float line_activity = 0.0;
    if (line_progress >= active_threshold) {
        // 越靠近进度的线条，活跃度越高
        line_activity = smoothstep(active_threshold - 0.2, active_threshold + 0.3, line_progress);
        line_activity = clamp((line_progress - active_threshold) / 0.3, 0.0, 1.0);
    }

    // 整体强度随progress增加
    float intensity = progress * line_activity;

    // === 3. 线条内的像素保留，线条外的逐渐透明 ===
    float line_mask = 0.0;
    if (dist_to_line < half_thickness) {
        // 线条中心区域完全不透明
        line_mask = 1.0;
    } else if (dist_to_line < half_thickness + trail_length / line_density) {
        // 边缘拖尾区域渐变透明
        float edge_t = (dist_to_line - half_thickness) / (trail_length / line_density);
        line_mask = 1.0 - smoothstep(0.0, 1.0, edge_t);
    } else {
        line_mask = 0.0;
    }

    // 未激活的线条保持完整，已激活的才被切割成线条
    float final_mask;
    if (line_activity < 0.05) {
        final_mask = 1.0; // 未激活区域保持完整图像
    } else {
        final_mask = line_mask;
    }

    // === 4. 水平扭曲（经典的动画线摆动效果）===
    vec2 deformed_uv = uv;

    if (intensity > 0.05) {
        // 使用正弦波产生类似"电流"的摆动感
        float phase = line_index * 2.0 + progress * 15.0;
        float offset_x = sin(phase + y * 30.0) * warp_strength * intensity;
        // 增加一个高频抖动，更有动画线感
        float jitter = sin(phase * 8.0 + progress * 40.0) * warp_strength * intensity * 0.5;
        deformed_uv.x += offset_x + jitter;
    }

    // === 5. 垂直方向压缩（线条被"吸"向中心）===
    if (intensity > 0.1 && line_activity > 0.1) {
        // 每条线向自己的中心压缩
        float compress_strength = intensity * 0.6;
        float compressed_t = line_y + (y - line_y) * (1.0 - compress_strength);
        deformed_uv.y = compressed_t;
    }

    // === 6. 采样颜色 ===
    vec4 color;
    if (deformed_uv.x < 0.0 || deformed_uv.x > 1.0 || deformed_uv.y < 0.0 || deformed_uv.y > 1.0) {
        color = vec4(0.0);
    } else {
        color = texture(TEXTURE, deformed_uv);
    }

    // 根据线条蒙版设置透明度
    color.a *= final_mask;

    // === 7. 添加发光效果（经典动画线的光晕）===
    if (intensity > 0.1 && line_activity > 0.1 && line_mask > 0.5) {
        float glow = glow_intensity * intensity * (1.0 - dist_to_line / half_thickness);
        // 白/青色发光
        color.rgb += vec3(0.8, 0.9, 1.0) * glow;
    }

    // === 8. 完全消失时的淡出 ===
    if (progress > 0.9) {
        color.a *= (1.0 - (progress - 0.9) / 0.1);
    }

    COLOR = color;
}