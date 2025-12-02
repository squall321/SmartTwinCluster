# 🚀 KooCAE Project Setup Guide

## 📋 **빠른 시작 (Quick Start)**

### **🐍 Python 버전 선택 (추천: 3.13)**

이 프로젝트는 **Python 3.13을 기본**으로 하며, Python 3.8+ 호환됩니다:

#### **Python 버전 확인만 하기**
```bash
# Windows
check_python_versions.bat

# Linux/macOS
./check_python_versions.sh
```

### **1단계: 자동 초기화 실행**

프로젝트를 처음 받았을 때 **단 한 번만** 실행하면 모든 설정이 완료됩니다:

#### **Windows 사용자**
```bash
# 방법 1: 통합 스크립트 (권장)
setup.bat

# 방법 2: 직접 실행
initialize_project.bat
```

#### **Linux/macOS 사용자**
```bash
# 방법 1: 통합 스크립트 (권장)  
chmod +x setup.sh
./setup.sh

# 방법 2: 직접 실행
chmod +x initialize_project.sh
./initialize_project.sh
```

### **2단계: VS Code에서 개발 시작**
1. VS Code에서 프로젝트 폴더 열기
2. **F5** 키를 눌러 Flask 서버 또는 C++ 디버깅 시작
3. 개발 완료! 🎉

### **🎆 사용 예시**

초기화 시 다음과 같은 Python 버전 선택 메뉴가 나타납니다:

```
🐍 Available Python versions:
  [1] Python 3.13 (Python 3.13.1) (Default ⭐)
  [2] Python 3.12 (Python 3.12.8)
  [3] Python 3.11 (Python 3.11.10)
  [4] System Python (Python 3.10.12)

💡 Recommendation: Python 3.13 is recommended for this project

Choose Python version [1-4] or press Enter for default (3.13): 
```

- **Enter 키**: 기본값 (3.13) 사용
- **숫자 입력**: 원하는 버전 선택
- **자동 검증**: 선택된 버전이 제대로 작동하는지 확인

---

## 🔧 **자동 초기화가 수행하는 작업**

### **✅ 플랫폼 자동 감지**
- Windows/Linux/macOS 자동 감지
- 플랫폼에 맞는 설정 자동 적용

### **✅ Python 환경 설정**
- **Python 버전 자동 감지**: 시스템의 모든 Python 설치 감지
- **버전 선택 메뉴**: 사용자가 원하는 Python 버전 선택 (기본: 3.13)
- **가상환경 자동 생성**: 선택된 버전으로 `venvWin` or `venv` 생성
- **pip 업그레이드**: 최신 pip로 자동 업그레이드
- **requirements.txt 의존성 자동 설치**: Flask, pybind11 등 핵심 패키지 검증

### **✅ VS Code 설정 자동 구성**
- 플랫폼별 컴파일러 경로 자동 설정
- Python 인터프리터 경로 자동 설정
- CMake 빌드 시스템 구성
- 디버깅 설정 자동 적용

### **✅ 빌드 도구 검증**
- **Windows**: Visual Studio Build Tools 자동 탐지
- **Linux**: GCC, CMake, Ninja 설치 상태 확인
- 누락된 도구에 대한 설치 가이드 제공

### **✅ 스크립트 실행 권한 설정**
- Linux/macOS: 모든 .sh 스크립트에 실행 권한 부여
- Windows: 배치 파일은 기본적으로 실행 가능

---

## 🌟 **플랫폼별 최적화**

### **🪟 Windows 최적화**
- **Visual Studio Build Tools** 자동 탐지 및 설정
- **MSVC 컴파일러** 환경 자동 구성
- **.pyd** 확장 모듈 지원
- **PowerShell** 터미널 기본 설정

### **🐧 Linux 최적화**
- **GCC/G++** 컴파일러 자동 감지
- **Ninja + CMake** 빌드 시스템 최적화
- **.so** 공유 라이브러리 지원
- **Bash** 터미널 기본 설정

### **🍎 macOS 호환성**
- Linux 스크립트와 동일한 환경 사용
- Homebrew 패키지 매니저 고려한 경로 설정

---

## 📁 **생성되는 파일 구조**

초기화 완료 후 다음 파일들이 생성/구성됩니다:

```
kooCAEWebServer/
├── 🐍 Python 가상환경
│   ├── venvWin/          # Windows용 가상환경
│   └── venv/             # Linux/macOS용 가상환경
│
├── ⚙️ VS Code 설정 (자동 적용)
│   ├── .vscode/
│   │   ├── settings.json           # 활성 설정 (플랫폼별 자동 선택)
│   │   ├── settings.windows.json   # Windows 전용 설정
│   │   ├── settings.linux.json     # Linux/macOS 전용 설정
│   │   ├── launch.json             # 디버깅 구성
│   │   └── tasks.json              # 빌드 태스크
│
├── 🛠️ 초기화 스크립트
│   ├── setup.bat / setup.sh        # 통합 시작 스크립트
│   ├── initialize_project.*        # 메인 초기화 스크립트
│   └── configure_vscode.*          # VS Code 구성 스크립트
│
└── 📋 요구사항 파일 (UTF-8)
    └── requirements.txt             # 인코딩 문제 해결됨
```

---

## 🚨 **문제 해결**

### **❌ "Python not found" 오류**

#### **Windows**
```bash
# 방법 1: 공식 설치 프로그램 (추천)
Python 3.13 설치: https://python.org/downloads/

# 방법 2: Microsoft Store
"Python 3.13" 검색 후 설치

# 방법 3: Chocolatey
choco install python --version=3.13.0

# 방법 4: Anaconda
https://anaconda.com/
```

#### **Linux**
```bash
# Ubuntu/Debian (추천)
sudo apt update
sudo apt install python3.13 python3.13-venv python3.13-pip
# 3.13이 없는 경우:
sudo apt install python3 python3-venv python3-pip

# Fedora/RHEL
sudo dnf install python3.13 python3.13-pip

# Arch Linux
sudo pacman -S python python-pip

# 소스에서 빌드
wget https://www.python.org/ftp/python/3.13.1/Python-3.13.1.tgz
tar -xzf Python-3.13.1.tgz
cd Python-3.13.1
./configure --enable-optimizations
make -j $(nproc)
sudo make altinstall
```

#### **macOS**
```bash
# Homebrew (추천)
brew install python@3.13

# 공식 설치 프로그램
https://python.org/downloads/macos/

# pyenv
pyenv install 3.13.1
pyenv global 3.13.1
```

### **❌ "Visual Studio not found" (Windows)**
- Visual Studio 2019 또는 2022 설치
- "C++를 사용한 데스크톱 개발" 워크로드 포함
- 또는 "Build Tools for Visual Studio" 설치

### **❌ "Build tools missing" (Linux)**
```bash
sudo apt-get update
sudo apt-get install build-essential cmake ninja-build gdb
```

### **❌ VS Code 설정이 적용되지 않음**
```bash
# 설정을 수동으로 다시 적용
# Windows
configure_vscode.bat

# Linux/macOS  
./configure_vscode.sh
```

### **❌ 가상환경 활성화 실패**
```bash
# Windows
venvWin\Scripts\activate

# Linux/macOS
source venv/bin/activate
```

---

## 🔄 **재설정이 필요한 경우**

프로젝트를 완전히 재설정하려면:

### **1. 기존 환경 정리**
```bash
# Windows
rmdir /s venvWin
del .vscode\settings.json

# Linux/macOS
rm -rf venv
rm .vscode/settings.json
```

### **2. 재초기화 실행**
```bash
# Windows
setup.bat

# Linux/macOS  
./setup.sh
```

---

## 🎯 **고급 사용자를 위한 팁**

### **🔧 수동 VS Code 설정**
플랫폼별 설정을 수동으로 전환하려면:
```bash
# Windows 설정 적용
copy .vscode\settings.windows.json .vscode\settings.json

# Linux 설정 적용  
cp .vscode/settings.linux.json .vscode/settings.json
```

### **🔍 환경 진단**
```bash
# 전체 환경 상태 점검
# Windows
test_environment.bat

# Linux/macOS
./test_environment.sh
```

### **⚡ 빠른 빌드 (초기화 완료 후)**
```bash  
# Windows
quick_build.bat

# Linux/macOS
./quick_build.sh
```

---

## 📞 **지원 및 문의**

설정 과정에서 문제가 발생하면:

1. **📋 자동 진단 실행**: `test_environment.*` 스크립트 사용
2. **📖 상세 가이드 참조**: `DEVELOPMENT_GUIDE.md` 확인
3. **🔧 수동 설정**: 각 단계별 수동 설정 가능

**성공적인 개발 환경 구축을 위해 최선을 다해 도와드리겠습니다! 🚀**
