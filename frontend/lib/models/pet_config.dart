class PetConfig {
  final String type;      // 펫 종류 식별자 (dog, cat, etc.)
  final String name;      // 표시 이름 (강아지, 고양이)
  final String defaultMode; // 기본 모드
  final List<String> availableModes; // 지원하는 훈련 모드 목록

  PetConfig({
    required this.type,
    required this.name,
    required this.defaultMode,
    required this.availableModes,
  });
}

// 펫 설정 데이터 (확장 시 여기에 추가)
final Map<String, PetConfig> PET_CONFIGS = {
  "dog": PetConfig(
    type: "dog",
    name: "강아지 🐶",
    defaultMode: "playing",
    availableModes: ["playing", "feeding", "interaction"],
  ),
  "cat": PetConfig(
    type: "cat",
    name: "고양이 🐱",
    defaultMode: "playing",
    availableModes: ["playing", "feeding", "interaction"], 
  ),
  // 추후 거북이, 앵무새 등 추가 가능
};
