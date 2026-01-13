import tensorflow as tf
import numpy as np
interpreter = tf.lite.Interpreter(model_path="/home/yang/PROJECT/pet_trainer/frontend/assets/models/pet_pose_int8.tflite")
interpreter.allocate_tensors()
# 랜덤 노이즈 입력 후 출력 확인
input_data = np.random.random((1, 640, 640, 3)).astype(np.float32)
interpreter.set_tensor(interpreter.get_input_details()[0]['index'], input_data)
interpreter.invoke()
output = interpreter.get_tensor(interpreter.get_output_details()[0]['index'])
print(np.max(output)) # 여기서도 0.0이 나오면 모델이 깨진 것입니다.