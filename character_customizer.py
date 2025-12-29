import cv2
import numpy as np
import os

def circular_crop(image, center, radius):
    """
    주어진 이미지에서 원형으로 영역을 잘라내고, 바깥쪽을 투명하게 처리합니다.

    :param image: 원본 이미지 (BGR)
    :param center: 원의 중심 좌표 (x, y)
    :param radius: 원의 반지름
    :return: 원형으로 잘라낸 이미지 (BGRA)
    """
    # 이미지를 4채널(BGRA)로 변환합니다.
    h, w, _ = image.shape
    image_bgra = cv2.cvtColor(image, cv2.COLOR_BGR2BGRA)

    # 원형 마스크 생성 (4채널)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    cv2.circle(mask, center, radius, (255, 255, 255, 255), -1)

    # 원본 이미지와 마스크를 AND 연산하여 원형 영역만 남깁니다.
    cropped_image = cv2.bitwise_and(image_bgra, mask)
    
    # 실제 잘라낼 영역 계산 (Bounding Box)
    x, y = center
    x1, y1 = max(0, x - radius), max(0, y - radius)
    x2, y2 = min(w, x + radius), min(h, y + radius)

    # 최종적으로 필요한 부분만 잘라냅니다.
    final_crop = cropped_image[y1:y2, x1:x2]

    return final_crop


def overlay_transparent(background, overlay, x, y):
    """
    배경 이미지 위에 투명한 오버레이 이미지를 합성합니다.

    :param background: 배경 이미지 (BGRA)
    :param overlay: 오버레이 이미지 (BGRA)
    :param x: 오버레이를 올릴 배경의 x 좌표
    :param y: 오버레이를 올릴 배경의 y 좌표
    """
    h, w, _ = overlay.shape
    
    # ROI(Region of Interest) 설정
    roi = background[y:y+h, x:x+w]

    # 오버레이 이미지에서 알파 채널(마스크) 분리
    overlay_bgr = overlay[:,:,0:3]
    alpha_mask = overlay[:,:,3] / 255.0
    
    # 알파 블렌딩 계산
    # 1. 마스크를 이용하여 배경에서 오버레이 될 부분을 어둡게 처리
    roi[:,:,0:3] = roi[:,:,0:3] * (1 - alpha_mask[:, :, np.newaxis])
    
    # 2. 오버레이 이미지에 마스크를 적용하여 배경과 합칠 부분만 남김
    overlay_masked = overlay_bgr * (alpha_mask[:, :, np.newaxis])

    # 3. 두 이미지를 합쳐서 최종 ROI를 만듦
    roi[:,:,0:3] += overlay_masked.astype(roi.dtype)


def main():
    # --- 1. 입력 이미지 로드 ---
    # 사용자 사진과 캐릭터 바디 템플릿 파일명을 지정합니다.
    # 스크립트와 같은 위치에 파일이 있어야 합니다.
    user_photo_path = 'user_photo.jpg'
    body_template_path = 'body_template.png'

    if not os.path.exists(user_photo_path):
        print(f"오류: 사용자 사진 파일 '{user_photo_path}'을(를) 찾을 수 없습니다.")
        print("스크립트와 같은 폴더에 'user_photo.jpg' 파일을 준비해주세요.")
        return
    if not os.path.exists(body_template_path):
        print(f"오류: 캐릭터 템플릿 파일 '{body_template_path}'을(를) 찾을 수 없습니다.")
        print("스크립트와 같은 폴더에 'body_template.png' 파일을 준비해주세요.")
        return
        
    user_photo = cv2.imread(user_photo_path)
    # PNG 파일의 투명도를 유지하기 위해 IMREAD_UNCHANGED 플래그 사용
    body_template = cv2.imread(body_template_path, cv2.IMREAD_UNCHANGED)

    # body_template이 3채널(BGR)이면 4채널(BGRA)로 변환
    if body_template.shape[2] == 3:
        body_template = cv2.cvtColor(body_template, cv2.COLOR_BGR2BGRA)
        
    # --- (가정) 변수 정의 ---
    # 사용자 사진에서 얼굴을 잘라낼 좌표와 반지름 (수동 지정)
    face_center_user_photo = (250, 200) # (x, y)
    face_radius_user_photo = 100

    # 캐릭터 바디 이미지에서 얼굴이 위치할 영역 (ROI)
    # (미리 정의된 값이라고 가정)
    face_roi_x = 150
    face_roi_y = 50
    face_roi_w = 120
    face_roi_h = 120

    print("1. 사용자 사진에서 얼굴 영역을 원형으로 자릅니다.")
    # --- 2. 원형 크롭 ---
    face_cropped = circular_crop(user_photo, face_center_user_photo, face_radius_user_photo)
    
    if face_cropped.shape[0] == 0 or face_cropped.shape[1] == 0:
        print("오류: 얼굴 영역을 제대로 자르지 못했습니다. 좌표를 확인하세요.")
        return

    print("2. 잘라낸 얼굴을 템플릿 크기에 맞게 리사이징합니다.")
    # --- 3. 리사이징 ---
    face_resized = cv2.resize(face_cropped, (face_roi_w, face_roi_h), interpolation=cv2.INTER_AREA)

    print("3. 얼굴과 캐릭터 바디를 합성합니다.")
    # --- 4. 이미지 합성 ---
    # 합성을 위해 복사본을 만듭니다.
    final_image = body_template.copy()
    overlay_transparent(final_image, face_resized, face_roi_x, face_roi_y)

    print("4. 최종 이미지를 'final_character.png' 파일로 저장합니다.")
    # --- 5. 결과 저장 ---
    # PNG 포맷으로 저장하여 투명도를 보존합니다.
    cv2.imwrite('final_character.png', final_image)
    
    print("\n작업 완료! 'final_character.png'를 확인하세요.")

if __name__ == '__main__':
    main()
