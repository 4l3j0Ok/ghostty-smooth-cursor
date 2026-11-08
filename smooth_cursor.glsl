// smooth_cursor.glsl
// Smooth (VS Code style) cursor blink + Neovide-like warp trail for Ghostty.
// Trail part derived from sahaj-b/cursor-shaders (MIT), see LICENSE.
//
// Required in the Ghostty config:
//   cursor-opacity = 0          (the shader draws the focused cursor itself)
//   cursor-style-blink = false  (the shader does the blinking)

// sRGB -> Linear conversion (needed because Ghostty passes sRGB values but the shader pipeline operates in linear color space)
vec3 sRGBToLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// --- BLINK CONFIGURATION ---
const float BLINK_ENABLED = 1.0;   // 0.0 = steady cursor
const float BLINK_HOLD = 0.5;      // seconds the cursor stays solid after moving/typing/focus
const float BLINK_PERIOD = 1.0;    // seconds per full fade out + fade in cycle
const float BLINK_MIN_ALPHA = 0.0; // opacity at the dimmest point of the blink
const float BLINK_PLATEAU = 0.8;   // higher = longer fully-visible/fully-hidden stretches (0.5 = pure sine)
const float BG_OPACITY = 0.92;     // your background-opacity (used to keep text visible over a block cursor)
const float HOLLOW_THICKNESS = 1.5; // outline width in pixels when unfocused

// --- GLIDE CONFIGURATION (the cursor slides between cells instead of jumping, e.g. while typing) ---
const float GLIDE_ENABLED = 1.0;
const float GLIDE_DURATION = 0.09; // seconds per move; higher = floatier

// --- TRAIL SELECTION (1.0 = on, 0.0 = off; they are drawn on top of each other) ---
const float WARP_ENABLED = 1.0;   // Neovide-like warp (corners jump at different speeds)
const float SWEEP_ENABLED = 1.0;  // shrinking parallelogram from the previous position
const float TAIL_ENABLED = 1.0;   // kitty-like comet tail

// --- SWEEP CONFIGURATION ---
const float SWEEP_DURATION = 0.2;
const float SWEEP_LENGTH = 0.5;
const float SWEEP_BLUR = 2.0;
const float SWEEP_THRESHOLD_MIN_DISTANCE = 1.5; // in cursor heights

// --- TAIL CONFIGURATION ---
const float TAIL_DURATION = 0.09;
const float TAIL_MAX_LENGTH = 0.2;
const float TAIL_BLUR = 2.0;
const float TAIL_THRESHOLD_MIN_DISTANCE = 1.5; // in cursor heights

// --- WARP CONFIGURATION ---
vec4 TRAIL_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a); // for custom color: vec4(0.2, 0.6, 1.0, 0.5); (wrap in sRGBToLinear for correct brightness)
const float DURATION = 0.2; // total animation time
const float TRAIL_SIZE = 0.8; // 0.0 = all corners move together. 1.0 = max smear (leading corners jump instantly)
const float THRESHOLD_MIN_DISTANCE = 1.5; // min distance to show trail (units of cursor height)
const float BLUR = 1.0; // blur size in pixels (for antialiasing)
const float TRAIL_THICKNESS = 1.0;  // 1.0 = full cursor height, 0.0 = zero height, >1.0 = funky aah
const float TRAIL_THICKNESS_X = 0.9;

const float FADE_ENABLED = 0.0; // 1.0 to enable fade gradient along the trail, 0.0 to disable
const float FADE_EXPONENT = 5.0; // exponent for fade gradient along the trail

// --- CONSTANTS for easing functions ---
const float PI = 3.14159265359;
const float C1_BACK = 1.70158;
const float C2_BACK = C1_BACK * 1.525;
const float C3_BACK = C1_BACK + 1.0;
const float C4_ELASTIC = (2.0 * PI) / 3.0;
const float C5_ELASTIC = (2.0 * PI) / 4.5;
const float SPRING_STIFFNESS = 9.0;
const float SPRING_DAMPING = 0.9;

// --- EASING FUNCTIONS ---

// // Linear
// float ease(float x) {
//     return x;
// }

// // EaseOutQuad
// float ease(float x) {
//     return 1.0 - (1.0 - x) * (1.0 - x);
// }

// EaseOutCubic (used by sweep)
float easeCubic(float x) {
    return 1.0 - pow(1.0 - x, 3.0);
}

// // EaseOutQuart
// float ease(float x) {
//     return 1.0 - pow(1.0 - x, 4.0);
// }

// // EaseOutQuint
// float ease(float x) {
//     return 1.0 - pow(1.0 - x, 5.0);
// }

// // EaseOutSine
// float ease(float x) {
//     return sin((x * PI) / 2.0);
// }

// // EaseOutExpo
// float ease(float x) {
//     return x == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x);
// }

// EaseOutCirc
float ease(float x) {
    return sqrt(1.0 - pow(x - 1.0, 2.0));
}

// // EaseOutBack
// float ease(float x) {
//     return 1.0 + C3_BACK * pow(x - 1.0, 3.0) + C1_BACK * pow(x - 1.0, 2.0);
// }

// // EaseOutElastic
// float ease(float x) {
//     return x == 0.0 ? 0.0
//          : x == 1.0 ? 1.0
//                     : pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * C4_ELASTIC) + 1.0;
// }

// // Parametric Spring
// float ease(float x) {
//     x = clamp(x, 0.0, 1.0);
//     float decay = exp(-SPRING_DAMPING * SPRING_STIFFNESS * x);
//     float freq = sqrt(SPRING_STIFFNESS * (1.0 - SPRING_DAMPING * SPRING_DAMPING));
//     float osc = cos(freq * 6.283185 * x) + (SPRING_DAMPING * sqrt(SPRING_STIFFNESS) / freq) * sin(freq * 6.283185 * x);
//     return 1.0 - decay * osc;
// }

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Based on Inigo Quilez's 2D distance functions article: https://iquilezles.org/articles/distfunctions2d/
// Potencially optimized by eliminating conditionals and loops to enhance performance and reduce branching
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

float getSdfConvexQuad(in vec2 p, in vec2 v1, in vec2 v2, in vec2 v3, in vec2 v4) {
    float s = 1.0;
    float d = dot(p - v1, p - v1);

    d = seg(p, v1, v2, s, d);
    d = seg(p, v2, v3, s, d);
    d = seg(p, v3, v4, s, d);
    d = seg(p, v4, v1, s, d);

    return s * sqrt(d);
}

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

// 1.0 when the top-right/bottom-left corners are the leading ones, else 0.0
float getTopVertexFlag(vec2 a, vec2 b) {
    float condition1 = step(b.x, a.x) * step(a.y, b.y);
    float condition2 = step(a.x, b.x) * step(b.y, a.y);
    return 1.0 - max(condition1, condition2);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float antialising(float distance, float blurAmount) {
  return 1. - smoothstep(0., normalize(vec2(blurAmount, blurAmount), 0.).x, distance);
}

// Determines animation duration based on a corner's alignment with the move direction(dot product)
// dot_val will be in [-2, 2]
// > 0.5 (1 or 2) = Leading
// > -0.5 (0)     = Side
// <= -0.5 (-1 or -2) = Trailing
float getDurationFromDot(float dot_val, float DURATION_LEAD, float DURATION_SIDE, float DURATION_TRAIL) {
    float isLead = step(0.5, dot_val);
    float isSide = step(-0.5, dot_val) * (1.0 - isLead);
    
    // Start with trailing duration
    float duration = mix(DURATION_TRAIL, DURATION_SIDE, isSide);
    // Mix in leading duration
    duration = mix(duration, DURATION_LEAD, isLead);
    return duration;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif

    // normalization & setup(-1, 1 coords)
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    vec2 centerCC = currentCursor.xy - (currentCursor.zw * offsetFactor);
    vec2 halfSizeCC = currentCursor.zw * 0.5;
    vec2 centerCP = previousCursor.xy - (previousCursor.zw * offsetFactor);
    vec2 halfSizeCP = previousCursor.zw * 0.5;

    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, halfSizeCC);
    
    float lineLength = distance(centerCC, centerCP);
    float minDist = currentCursor.w * THRESHOLD_MIN_DISTANCE;
    
    vec4 newColor = vec4(fragColor);

    float baseProgress = iTime - iTimeCursorChange;
    
    if (WARP_ENABLED > 0.5 && lineLength > minDist && baseProgress < DURATION - 0.001) {
        // defining corners of cursors

        // Y (Height) with TRAIL_THICKNESS
        float cc_half_height = currentCursor.w * 0.5;
        float cc_center_y = currentCursor.y - cc_half_height;
        float cc_new_half_height = cc_half_height * TRAIL_THICKNESS;
        float cc_new_top_y = cc_center_y + cc_new_half_height;
        float cc_new_bottom_y = cc_center_y - cc_new_half_height;

        // X (Width) with TRAIL_THICKNESS
        float cc_half_width = currentCursor.z * 0.5;
        float cc_center_x = currentCursor.x + cc_half_width;
        float cc_new_half_width = cc_half_width * TRAIL_THICKNESS_X;
        float cc_new_left_x = cc_center_x - cc_new_half_width;
        float cc_new_right_x = cc_center_x + cc_new_half_width;

        vec2 cc_tl = vec2(cc_new_left_x, cc_new_top_y);
        vec2 cc_tr = vec2(cc_new_right_x, cc_new_top_y);
        vec2 cc_bl = vec2(cc_new_left_x, cc_new_bottom_y);
        vec2 cc_br = vec2(cc_new_right_x, cc_new_bottom_y);

        // same thing for previous cursor
        float cp_half_height = previousCursor.w * 0.5;
        float cp_center_y = previousCursor.y - cp_half_height;
        float cp_new_half_height = cp_half_height * TRAIL_THICKNESS;
        float cp_new_top_y = cp_center_y + cp_new_half_height;
        float cp_new_bottom_y = cp_center_y - cp_new_half_height;

        float cp_half_width = previousCursor.z * 0.5;
        float cp_center_x = previousCursor.x + cp_half_width;
        float cp_new_half_width = cp_half_width * TRAIL_THICKNESS_X;
        float cp_new_left_x = cp_center_x - cp_new_half_width;
        float cp_new_right_x = cp_center_x + cp_new_half_width;

        vec2 cp_tl = vec2(cp_new_left_x, cp_new_top_y);
        vec2 cp_tr = vec2(cp_new_right_x, cp_new_top_y);
        vec2 cp_bl = vec2(cp_new_left_x, cp_new_bottom_y);
        vec2 cp_br = vec2(cp_new_right_x, cp_new_bottom_y);

        // calculating durations for every corner
        const float DURATION_TRAIL = DURATION;
        const float DURATION_LEAD = DURATION * (1.0 - TRAIL_SIZE);
        const float DURATION_SIDE = (DURATION_LEAD + DURATION_TRAIL) / 2.0;

        vec2 moveVec = centerCC - centerCP;
        vec2 s = sign(moveVec);

        // dot products for each corner, determining alignment with movement direction
        float dot_tl = dot(vec2(-1., 1.), s);
        float dot_tr = dot(vec2( 1., 1.), s);
        float dot_bl = dot(vec2(-1.,-1.), s);
        float dot_br = dot(vec2( 1.,-1.), s);

        // assign durations based on dot products
        float dur_tl = getDurationFromDot(dot_tl, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
        float dur_tr = getDurationFromDot(dot_tr, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
        float dur_bl = getDurationFromDot(dot_bl, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
        float dur_br = getDurationFromDot(dot_br, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);

        // check direction of horizontal movement
        float isMovingRight = step(0.5, s.x);
        float isMovingLeft  = step(0.5, -s.x);

        // calculate vertical-rail durations
        float dot_right_edge = (dot_tr + dot_br) * 0.5;
        float dur_right_rail = getDurationFromDot(dot_right_edge, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
        
        float dot_left_edge = (dot_tl + dot_bl) * 0.5;
        float dur_left_rail = getDurationFromDot(dot_left_edge, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);

        float final_dur_tl = mix(dur_tl, dur_left_rail, isMovingLeft);
        float final_dur_bl = mix(dur_bl, dur_left_rail, isMovingLeft);
        
        float final_dur_tr = mix(dur_tr, dur_right_rail, isMovingRight);
        float final_dur_br = mix(dur_br, dur_right_rail, isMovingRight);

        // calculate progress for each corner based on the duration and time since cursor change
        float prog_tl = ease(clamp(baseProgress / final_dur_tl, 0.0, 1.0));
        float prog_tr = ease(clamp(baseProgress / final_dur_tr, 0.0, 1.0));
        float prog_bl = ease(clamp(baseProgress / final_dur_bl, 0.0, 1.0));
        float prog_br = ease(clamp(baseProgress / final_dur_br, 0.0, 1.0));

        // get the trial corner positions based on progress
        vec2 v_tl = mix(cp_tl, cc_tl, prog_tl);
        vec2 v_tr = mix(cp_tr, cc_tr, prog_tr);
        vec2 v_br = mix(cp_br, cc_br, prog_br);
        vec2 v_bl = mix(cp_bl, cc_bl, prog_bl);

        // DRAWING THE TRAIL
        float sdfTrail = getSdfConvexQuad(vu, v_tl, v_tr, v_br, v_bl);

        // --- FADE GRADIENT CALCULATION ---
        vec2 fragVec = vu - centerCP;
        
        // project fragment onto movement vector, normalize to [0, 1]
        // 0.0 at tail, 1.0 at head
        // tiny epsilon to avoid division by zero if moveVec is (0,0)
        float fadeProgress = clamp(dot(fragVec, moveVec) / (dot(moveVec, moveVec) + 1e-6), 0.0, 1.0);

        vec4 trail = TRAIL_COLOR;
        
        float effectiveBlur = BLUR;
        if (BLUR < 2.5) {
          // no antialising on horizontal/vertical movement, fixes 'pulse' like thing on end cursor
          float isDiagonal = abs(s.x) * abs(s.y); // 1.0 if diagonal, 0.0 if H/V
          float effectiveBlur = mix(0.0, BLUR, isDiagonal);
        }
        float shapeAlpha = antialising(sdfTrail, effectiveBlur); // shape mask

        if (FADE_ENABLED > 0.5) {
            // apply fade gradient along the trail
            // float fadeStart = 0.2;
            // float easedProgress = smoothstep(fadeStart, 1.0, fadeProgress);
            // easedProgress = pow(2.0, 10.0 * (fadeProgress - 1.0));
            float easedProgress = pow(fadeProgress, FADE_EXPONENT);
            trail.a *= easedProgress;
        }

        float finalAlpha = trail.a * shapeAlpha;

        // newColor.a to preserve the background alpha.
        newColor = mix(newColor, vec4(trail.rgb, newColor.a), finalAlpha);
    }

    // --- SWEEP TRAIL ---
    float sinceMove = iTime - iTimeCursorChange;
    if (SWEEP_ENABLED > 0.5 && lineLength > currentCursor.w * SWEEP_THRESHOLD_MIN_DISTANCE && sinceMove < SWEEP_DURATION) {
        float shrinkFactor = easeCubic(clamp(sinceMove / SWEEP_DURATION, 0.0, 1.0));

        vec2 sDelta = abs(centerCC - centerCP);
        float isStraightMove = max(step(sDelta.y, 0.001), step(sDelta.x, 0.001));

        float topFlag = getTopVertexFlag(currentCursor.xy, previousCursor.xy);
        float bottomFlag = 1.0 - topFlag;
        vec2 v0 = vec2(currentCursor.x + currentCursor.z * topFlag, currentCursor.y - currentCursor.w);
        vec2 v1 = vec2(currentCursor.x + currentCursor.z * bottomFlag, currentCursor.y);
        vec2 v2_full = vec2(previousCursor.x + currentCursor.z * bottomFlag, previousCursor.y);
        vec2 v3_full = vec2(previousCursor.x + currentCursor.z * topFlag, previousCursor.y - previousCursor.w);

        vec2 v2_anim = mix(mix(v1, v2_full, SWEEP_LENGTH), v1, shrinkFactor);
        vec2 v3_anim = mix(mix(v0, v3_full, SWEEP_LENGTH), v0, shrinkFactor);
        float sdfDiag = getSdfParallelogram(vu, v0, v1, v2_anim, v3_anim);

        vec2 minC = min(centerCP, centerCC);
        vec2 maxC = max(centerCP, centerCC);
        vec2 boxSizeFull = (maxC - minC) + currentCursor.zw;
        vec2 boxCenterFull = (minC + maxC) * 0.5;
        vec2 animSize = mix(mix(currentCursor.zw, boxSizeFull, SWEEP_LENGTH), currentCursor.zw, shrinkFactor);
        vec2 animCenter = mix(mix(centerCC, boxCenterFull, SWEEP_LENGTH), centerCC, shrinkFactor);
        float sdfRect = getSdfRectangle(vu, animCenter, animSize * 0.5);

        float sdfSweep = mix(sdfDiag, sdfRect, isStraightMove);
        newColor = mix(newColor, vec4(TRAIL_COLOR.rgb, newColor.a), TRAIL_COLOR.a * antialising(sdfSweep, SWEEP_BLUR));
    }

    // --- TAIL TRAIL ---
    if (TAIL_ENABLED > 0.5 && lineLength > currentCursor.w * TAIL_THRESHOLD_MIN_DISTANCE && sinceMove < TAIL_DURATION) {
        float tProgress = clamp(sinceMove / TAIL_DURATION, 0.0, 1.0);
        float tailDelayFactor = TAIL_MAX_LENGTH / lineLength;
        float isLongMove = step(TAIL_MAX_LENGTH, lineLength);

        float headEased = mix(1.0, ease(tProgress), isLongMove);
        float tailEased = mix(ease(tProgress), ease(smoothstep(tailDelayFactor, 1.0, tProgress)), isLongMove);

        vec2 tDelta = abs(centerCC - centerCP);
        float isStraightMove = max(step(tDelta.y, 0.001), step(tDelta.x, 0.001));

        vec2 headPos = mix(previousCursor.xy, currentCursor.xy, headEased);
        vec2 tailPos = mix(previousCursor.xy, currentCursor.xy, tailEased);

        float trLeading = getTopVertexFlag(currentCursor.xy, previousCursor.xy);
        float blLeading = 1.0 - trLeading;
        vec2 v0 = vec2(headPos.x + currentCursor.z * trLeading, headPos.y - currentCursor.w);
        vec2 v1 = vec2(headPos.x + currentCursor.z * blLeading, headPos.y);
        vec2 v2 = vec2(tailPos.x + currentCursor.z * blLeading, tailPos.y);
        vec2 v3 = vec2(tailPos.x + currentCursor.z * trLeading, tailPos.y - previousCursor.w);
        float sdfDiag = getSdfParallelogram(vu, v0, v1, v2, v3);

        vec2 headCenter = mix(centerCP, centerCC, headEased);
        vec2 tailCenter = mix(centerCP, centerCC, tailEased);
        vec2 minC = min(headCenter, tailCenter);
        vec2 maxC = max(headCenter, tailCenter);
        float sdfRect = getSdfRectangle(vu, (minC + maxC) * 0.5, ((maxC - minC) + currentCursor.zw) * 0.5);

        float sdfTail = mix(sdfDiag, sdfRect, isStraightMove);
        newColor = mix(newColor, vec4(TRAIL_COLOR.rgb, newColor.a), TRAIL_COLOR.a * antialising(sdfTail, TAIL_BLUR));
    }

    // cursor rectangle, gliding from the previous position to the current one
    float sdfCursor = sdfCurrentCursor;
    if (GLIDE_ENABLED > 0.5 && dot(previousCursor.zw, previousCursor.zw) > 0.0) {
        float glide = easeCubic(clamp(sinceMove / GLIDE_DURATION, 0.0, 1.0));
        vec2 glideCenter = mix(centerCP, centerCC, glide);
        vec2 glideHalf = mix(previousCursor.zw, currentCursor.zw, glide) * 0.5;
        sdfCursor = getSdfRectangle(vu, glideCenter, glideHalf);
    }

    // punch hole on the trails, so the cursor is drawn on top
    newColor = mix(newColor, fragColor, step(sdfCursor, 0.));

    // --- CURSOR (drawn by the shader, native cursor is hidden via cursor-opacity = 0) ---
    bool isHollow = (iFocus == 0) || (iCurrentCursorStyle == CURSORSTYLE_BLOCK_HOLLOW);
    bool isHidden = (iCursorVisible == 0) || (iCurrentCursorStyle == CURSORSTYLE_LOCK);

    if (!isHidden) {
        float sinceChange = min(iTime - iTimeCursorChange, iTime - iTimeFocus);
        float blink = 1.0;
        if (BLINK_ENABLED > 0.5 && !isHollow && sinceChange > BLINK_HOLD) {
            float phase = (sinceChange - BLINK_HOLD) / BLINK_PERIOD;
            float wave = 0.5 + BLINK_PLATEAU * cos(6.2831853 * phase);
            blink = mix(BLINK_MIN_ALPHA, 1.0, smoothstep(0.0, 1.0, clamp(wave, 0.0, 1.0)));
        }

        vec4 cursorColor = vec4(sRGBToLinear(iCurrentCursorColor.rgb), 1.0);
        float coverage;
        float textMask = 0.0;

        if (isHollow) {
            float th = normalize(vec2(HOLLOW_THICKNESS), 0.).x;
            float ring = abs(sdfCursor + th * 0.5) - th * 0.5;
            coverage = antialising(ring, 1.0);
        } else {
            coverage = antialising(sdfCursor, 1.0);
            // keep the glyph under a block cursor visible
            if (iCurrentCursorStyle == CURSORSTYLE_BLOCK) {
                float inside = 1.0 - step(0.0, sdfCursor);
                textMask = smoothstep(min(BG_OPACITY, 0.999), 1.0, texture(iChannel0, fragCoord.xy / iResolution.xy).a) * inside;
            }
        }

        newColor = mix(newColor, cursorColor, coverage * blink * (1.0 - textMask));
    }

    fragColor = newColor;
}
