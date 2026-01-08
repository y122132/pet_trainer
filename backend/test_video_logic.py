import cv2
import sys
import os
import numpy as np
import argparse
import time

# Add backend directory to sys.path to allow imports from 'app'
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)
# Parent dir fallback
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.append(parent_dir)

try:
    from app.ai_core.vision.detector import process_frame
except ImportError as e:
    print(f"Error importing detector: {e}")
    sys.exit(1)

def draw_skeleton(frame, keypoints, connections, color=(0, 255, 0)):
    h, w, _ = frame.shape
    # Draw connections
    for i, j in connections:
        if i < len(keypoints) and j < len(keypoints):
             pt1 = keypoints[i]
             pt2 = keypoints[j]
             # conf check (index 2 is conf)
             conf1 = pt1[2] if len(pt1) > 2 else 1.0
             conf2 = pt2[2] if len(pt2) > 2 else 1.0
             
             if conf1 > 0.35 and conf2 > 0.35:
                 x1, y1 = int(pt1[0] * w), int(pt1[1] * h)
                 x2, y2 = int(pt2[0] * w), int(pt2[1] * h)
                 cv2.line(frame, (x1, y1), (x2, y2), color, 2)
    
    # Draw points
    for kp in keypoints:
        conf = kp[2] if len(kp) > 2 else 1.0
        if conf > 0.35:
            x, y = int(kp[0] * w), int(kp[1] * h)
            cv2.circle(frame, (x, y), 3, color, -1)

def main():
    parser = argparse.ArgumentParser(description="Test Pet Trainer AI Detector")
    parser.add_argument("--video", type=str, required=True, help="Path to video file")
    parser.add_argument("--mode", type=str, default="playing", choices=["playing", "feeding", "interaction"], help="Game mode")
    parser.add_argument("--output", type=str, default="auto", help="Output video path (optional)")
    parser.add_argument("--show", action="store_true", help="Show window (requires UI)")
    
    args = parser.parse_args()
    
    input_path = args.video
    if not os.path.exists(input_path):
        print(f"Error: File not found: {input_path}")
        return

    # Check validity
    ext = os.path.splitext(input_path)[1].lower()
    is_image = ext in ['.jpg', '.jpeg', '.png', '.bmp', '.webp']
    
    cap = None
    frame = None
    
    if is_image:
        frame = cv2.imread(input_path)
        if frame is None:
            print(f"Error reading image: {input_path}")
            return
        width, height = frame.shape[1], frame.shape[0]
        fps = 0
        total_frames = 1
    else:
        cap = cv2.VideoCapture(input_path)
        if not cap.isOpened():
            print(f"Error opening video: {input_path}")
            return
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps == 0: fps = 30
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    # Output Setup
    if args.output == "auto":
        dir_name = os.path.dirname(os.path.abspath(input_path))
        base_name = os.path.splitext(os.path.basename(input_path))[0]
        out_ext = ".jpg" if is_image else ".avi"
        out_path = os.path.join(dir_name, f"output_{base_name}{out_ext}")
    else:
        out_path = args.output
        
    out = None
    if not is_image:
        fourcc = cv2.VideoWriter_fourcc(*'MJPG')
        out = cv2.VideoWriter(out_path, fourcc, fps, (width, height))
        
    print(f"Processing: {input_path} -> {out_path}")
    print(f"Mode: {args.mode}, Resolution: {width}x{height}, Type: {'IMAGE' if is_image else 'VIDEO'}")

    # --- Connections (COCO Standard 17) ---
    # 0:Nose, 1:LEye, 2:REye, 3:LEar, 4:REar, 5:LShld, 6:RShld
    # 7:LElb, 8:RElb, 9:LWrist, 10:RWrist, 11:LHip, 12:RHip
    # 13:LKnee, 14:RKnee, 15:LAnk, 16:RAnk
    pet_connections = [
        [0, 1], [0, 2], # Nose-Eyes
        [1, 3], [2, 4], # Eyes-Ears
        [5, 6], # Shoulders
        [5, 7], [7, 9], # Left Arm (Front Leg)
        [6, 8], [8, 10], # Right Arm (Front Leg)
        [11, 12], # Hips
        [5, 11], [6, 12], # Torso
        [11, 13], [13, 15], # Left Leg (Back Leg)
        [12, 14], [14, 16]  # Right Leg (Back Leg)
    ]
    human_connections = pet_connections # Humans share same topology in COCO

    # Stats
    stats = {
        "total_frames": 0,
        "pet_detected": 0,
        "interaction_success": 0,
        "inference_time": []
    }

    frame_idx = 0
    start_time_all = time.time()
    
    # [NEW] Anti-Flickering State for Test
    vision_state = {
        "last_pet_box": None,
        "missing_count": 0,
        "is_tracking": False,
        "last_response": None
    }
    
    # Loop Logic (Video vs Image)
    while True:
        if not is_image:
            if not cap.isOpened(): break
            ret, frame = cap.read()
            if not ret: break
        else:
            # Image mode: run once then break
            if frame_idx > 0: break
        
        t0 = time.time()
        
        # Encode
        _, buffer = cv2.imencode('.jpg', frame)
        image_bytes = buffer.tobytes()
        
        # Process
        result = process_frame(
            image_bytes, 
            mode=args.mode, 
            target_class_id=16, # Default Dog
            process_interval=1, 
            frame_index=frame_idx,
            vision_state=vision_state # [NEW] Pass State
        )
        
        dt = time.time() - t0
        stats["inference_time"].append(dt)
        stats["total_frames"] += 1
        
        if result.get('bbox') and any(b[5] == 16 for b in result['bbox']):
            stats["pet_detected"] += 1
            
        if result.get("success"):
            stats["interaction_success"] += 1

        # Draw
        # 1. BBox
        for box in result.get('bbox', []):
            x1, y1, x2, y2, conf, cls_id = box
            ix1, iy1 = int(x1*width), int(y1*height)
            ix2, iy2 = int(x2*width), int(y2*height)
            
            color = (255, 0, 0)
            if cls_id == 16: color = (0, 165, 255) # Dog: Orange
            elif cls_id == 0: color = (0, 255, 0) # Human: Green
            
            cv2.rectangle(frame, (ix1, iy1), (ix2, iy2), color, 2)
            label = f"ID:{int(cls_id)} {conf:.2f}"
            cv2.putText(frame, label, (ix1, iy1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)

        # 2. Skeletons
        if 'pet_keypoints' in result:
            draw_skeleton(frame, result['pet_keypoints'], pet_connections, (0, 165, 255))
        if 'human_keypoints' in result:
            draw_skeleton(frame, result['human_keypoints'], human_connections, (0, 255, 0))

        # 3. Message
        msg = result.get('message', '')
        fb = result.get('feedback_message', '')
        success = result.get('success', False)
        
        # Header Bar
        header_color = (0, 100, 0) if success else (0, 0, 0)
        cv2.rectangle(frame, (0, 0), (width, 50), header_color, -1)
        cv2.putText(frame, f"[{args.mode.upper()}] {msg}", (10, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        
        # Footer Bar (Feedback Code)
        if fb:
            cv2.putText(frame, f"Code: {fb}", (10, height-20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)

        if is_image:
            cv2.imwrite(out_path, frame)
        else:
            out.write(frame)
            
        if args.show:
            cv2.imshow("Preview", frame)
            if cv2.waitKey(1 if not is_image else 0) & 0xFF == ord('q'): break
            
        frame_idx += 1
        if not is_image and frame_idx % 30 == 0:
            print(f"Processed {frame_idx}/{total_frames} frames...", end='\r')

    if cap: cap.release()
    if out: out.release()
    if args.show: cv2.destroyAllWindows()
    
    total_time = time.time() - start_time_all
    avg_inf = sum(stats["inference_time"]) / len(stats["inference_time"]) if stats["inference_time"] else 0
    
    print(f"\n\n=== Analysis Report ===")
    print(f"Total Frames: {stats['total_frames']}")
    print(f"Pet Detected: {stats['pet_detected']} ({stats['pet_detected']/stats['total_frames']*100:.1f}%)")
    print(f"Interaction Success: {stats['interaction_success']}")
    print(f"Avg Inference Time: {avg_inf*1000:.1f}ms per frame")
    print(f"Total Processing Time: {total_time:.1f}s")
    print(f"Saved to: {out_path}")

if __name__ == "__main__":
    main()
