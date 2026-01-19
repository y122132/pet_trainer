import time
import numpy as np

class TrainingSessionManager:
    """
    개별 유저의 훈련 세션 FSM 상태 관리 클래스
    """
    def __init__(self):
        self.state = "READY"
        self.state_start_time = None
        self.last_detected_time = None
        self.last_interaction_time = time.time()
        
        self.vision_state = {
            "last_pet_box": None,
            "missing_count": 0,
            "is_tracking": False,
            "last_response": None,
            "best_frame_data": None,
            "best_conf": 0.0,
            "best_bbox": []
        }

    def reset(self):
        self.state = "READY"
        self.state_start_time = None
        self.last_detected_time = None
        self.vision_state["is_tracking"] = False
        self.vision_state["best_frame_data"] = None
        self.vision_state["best_conf"] = 0.0
    
    def update_best_shot(self, image_bytes, conf_score, bbox):
        if image_bytes and (self.vision_state["best_frame_data"] is None or conf_score > self.vision_state["best_conf"]):
            self.vision_state["best_conf"] = conf_score
            self.vision_state["best_frame_data"] = image_bytes
            self.vision_state["best_bbox"] = bbox
            # print(f"[BestShot] Updated! Conf: {conf_score:.4f}", flush=True)

    def process_fsm(self, vision_result: dict, image_bytes: bytes, current_time: float) -> dict:
        """
        비전 결과와 현재 시간을 기반으로 상태를 전이하고 응답 메시지를 반환
        """
        response = vision_result.copy()
        is_success_vision = vision_result.get("success", False)
        
        # Cooldown handling logic should be done by the caller or wrapped here?
        # Let's assume the caller handles the 'COOLDOWN' state check before calling here, 
        # or we handle it here. Let's handle it here for encapsulation.
        
        if self.state == "COOLDOWN":
            elapsed = current_time - (self.state_start_time or current_time)
            if elapsed >= 3.0:
                self.state = "READY"
                self.state_start_time = None
            else:
                response["status"] = "keep"
                response["message"] = f"잠시 휴식... {3.0 - elapsed:.1f}초"
                response["is_specific_feedback"] = True
                return response

        if is_success_vision:
            self.last_interaction_time = current_time
            self.last_detected_time = current_time
            
            if self.state == "READY":
                self.state = "DETECTING"
                response.update({"status": "detecting", "message": "동작 감지 시작!"})
            
            elif self.state == "DETECTING":
                self.state = "STAY"
                self.state_start_time = current_time
                response.update({"status": "stay", "message": "좋아요, 자세를 3초간 유지하세요!"})
            
            elif self.state == "STAY":
                hold_duration = current_time - self.state_start_time
                if hold_duration >= 3:
                    self.state = "SUCCESS"
                    response.update({"status": "success"}) # Will trigger success logic in socket
                else:
                    response.update({"status": "stay", "message": f"자세 유지... {3 - hold_duration:.1f}초"})
                    # Best Shot logic
                    self.update_best_shot(image_bytes, vision_result.get("conf_score", 0.0), vision_result.get("bbox", []))
                    
        else:
            if self.state == "STAY":
                # Grace Period Check
                if self.last_detected_time and (current_time - self.last_detected_time > 0.8):
                    # Fail
                    self.state = "READY"
                    self.state_start_time = None
                    self.vision_state["best_frame_data"] = None
                    self.vision_state["best_conf"] = 0.0
                    
                    response.update({"status": "fail", "message": "동작이 끊겼습니다."})
                    
                    self.last_interaction_time = current_time
                    # Feedback trigger logic needs to be signaled to caller
                    response["need_feedback"] = "pose_unstable" 
                    
                else:
                    # Grace Period Active
                    if self.state_start_time:
                         hold_duration = current_time - self.state_start_time
                         response.update({
                            "status": "stay", 
                            "message": f"자세 유지... {1 - hold_duration:.1f}초 (인식 불안정)"
                        })
            
            elif self.state == "DETECTING":
                self.state = "READY"
            
            if self.state == "READY":
                if not vision_result.get("is_specific_feedback", False):
                    response.pop("message", None)
                response.update({"status": "fail"})

        return response

    def set_success(self, current_time: float):
        self.state = "SUCCESS"
        self.last_interaction_time = current_time
        
    def start_cooldown(self, current_time: float):
        self.state = "COOLDOWN"
        self.state_start_time = current_time
        self.last_detected_time = None
