import cv2
import sys
import os
import numpy as np

# Add backend directory to sys.path to allow imports from 'app'
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    from app.ai_core.vision.detector import process_frame
except ImportError:
    # If run from backend parent dir
    sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    from app.ai_core.vision.detector import process_frame

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

def main(video_path):
    if not os.path.exists(video_path):
        print(f"File not found: {video_path}")
        return

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Error opening video: {video_path}")
        return

    # Video Writer Setup (Lazy Init)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps == 0: fps = 30
    
    out = None
    # [Fix] Use absolute path and .avi for better compatibility (MJPG)
    dir_name = os.path.dirname(os.path.abspath(video_path))
    base_name = os.path.splitext(os.path.basename(video_path))[0]
    out_path = os.path.join(dir_name, f"output_{base_name}.avi")
    
    print(f"Input: {video_path}")
    print(f"Meta Resolution: {width}x{height}, FPS: {fps}")

    # --- Skeleton Topology (0-based) ---
    # Pet (Matched with camera_painters.dart)
    pet_connections = [
        [2, 0], [2, 1], # Face
        [2, 3], # Nose-Neck
        [3, 4], # Spine
        [3, 5], [5, 6], [6, 7], # FL
        [3, 8], [8, 9], [9, 10], # FR
        [4, 11], [11, 12], [12, 13], # BL
        [4, 14], [14, 15], [15, 16] # BR
    ]

    # Human (Standard COCO)
    human_connections = [
        [11, 13], [13, 15], [12, 14], [14, 16], [11, 12], 
        [5, 6], [5, 11], [6, 12], [5, 7], [7, 9], [6, 8], [8, 10]
    ]

    frame_idx = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
            
        # Lazy Init Writer (to handle rotation/metadata mismatch)
        if out is None:
             h, w, _ = frame.shape
             # Codec: MJPG is safest for Linux/OpenCV without extra ffmpeg setup
             fourcc = cv2.VideoWriter_fourcc(*'MJPG')
             out = cv2.VideoWriter(out_path, fourcc, fps, (w, h))
             
             if not out.isOpened():
                 print(f"Error: Could not create video writer for {out_path}")
                 break
             print(f"Video Writer initialized: {w}x{h} @ {fps}fps (MJPG)")

        # Encode to bytes for process_frame (Simulate Frontend)
        _, buffer = cv2.imencode('.jpg', frame)
        image_bytes = buffer.tobytes()
        
        # Process (Simulate 'playing' mode)
        # You can change mode="feeding", "interaction"
        result = process_frame(
            image_bytes, 
            mode="playing", 
            target_class_id=16, # Dog
            process_interval=1, 
            frame_index=frame_idx
        )
        
        # Draw Results
        if result['success'] or result.get('bbox') or True: # Always draw debugging info
             # Draw BBox
             for box in result.get('bbox', []):
                 x1, y1, x2, y2, conf, cls_id = box
                 ix1, iy1 = int(x1*width), int(y1*height)
                 ix2, iy2 = int(x2*width), int(y2*height)
                 cv2.rectangle(frame, (ix1, iy1), (ix2, iy2), (255, 0, 0), 2)
                 label = f"Class {int(cls_id)} {conf:.2f}"
                 cv2.putText(frame, label, (ix1, iy1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255,0,0), 1)

             # Draw Pet Skeleton
             if 'pet_keypoints' in result:
                 draw_skeleton(frame, result['pet_keypoints'], pet_connections, (0, 165, 255)) # Orange

             # Draw Human Skeleton
             if 'human_keypoints' in result:
                 draw_skeleton(frame, result['human_keypoints'], human_connections, (0, 255, 0)) # Green

             # Draw Status Message
             msg = result.get('message', '')
             if msg:
                cv2.rectangle(frame, (0, 0), (width, 40), (0,0,0), -1)
                cv2.putText(frame, msg, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
             
             # Draw Feedback
             fb = result.get('feedback_message', '')
             if fb:
                 cv2.putText(frame, f"FB: {fb}", (10, height-20), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

        out.write(frame)
        frame_idx += 1
        
        if frame_idx % 30 == 0:
            print(f"Processed {frame_idx} frames...")

    cap.release()
    out.release()
    print(f"Done. Saved to {out_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_video_logic.py <video_path>")
        print("Example: python test_video_logic.py my_dog.mp4")
    else:
        main(sys.argv[1])
