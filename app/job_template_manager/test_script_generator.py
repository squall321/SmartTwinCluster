"""
ScriptGenerator 테스트

실제 템플릿을 로드하여 스크립트 생성 테스트
"""

import sys
from pathlib import Path

# src 디렉토리를 Python path에 추가
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from utils.yaml_loader import YAMLLoader
from utils.script_generator import ScriptGenerator


def test_script_generation():
    """스크립트 생성 테스트"""
    print("=" * 80)
    print("ScriptGenerator Test")
    print("=" * 80)
    print()

    # 1. Template 로드
    print("1. Loading template...")
    loader = YAMLLoader()
    templates = loader.scan_templates()

    if not templates:
        print("❌ No templates found!")
        return

    template_obj = templates[0]
    print(f"✓ Loaded template: {template_obj.template.name}")
    print(f"  ID: {template_obj.template.id}")
    print(f"  Category: {template_obj.template.category}")
    print()

    # 2. Slurm 설정 (TemplateEditorWidget에서 가져올 설정)
    print("2. Preparing Slurm configuration...")
    slurm_config = {
        'partition': 'compute',
        'nodes': 1,
        'ntasks': 4,
        'mem': '32G',
        'time': '02:00:00',
        'gpus': 0,
    }
    print(f"✓ Slurm config: {slurm_config}")
    print()

    # 3. 업로드된 파일 시뮬레이션
    print("3. Simulating uploaded files...")
    uploaded_files = {
        'training_script': Path('/tmp/train.py'),
        'dataset': Path('/tmp/dataset.tar.gz'),
    }
    print(f"✓ Uploaded files:")
    for key, path in uploaded_files.items():
        print(f"  - {key}: {path}")
    print()

    # 4. 스크립트 생성
    print("4. Generating Slurm script...")
    generator = ScriptGenerator()

    script = generator.generate(
        template_obj=template_obj,
        slurm_config=slurm_config,
        uploaded_files=uploaded_files,
        job_name='test_pytorch_training',
        apptainer_image_path='/opt/apptainers/KooSimulationPython313.sif'
    )

    print(f"✓ Generated script ({len(script)} bytes)")
    print()

    # 5. 스크립트 출력
    print("5. Generated Script:")
    print("=" * 80)
    print(script)
    print("=" * 80)
    print()

    # 6. 스크립트 저장
    print("6. Saving script...")
    output_path = Path(__file__).parent / 'output' / 'test_job.sh'
    saved_path = generator.save_script(script, output_path)
    print(f"✓ Script saved to: {saved_path}")
    print()

    # 7. Job 메타데이터 생성
    print("7. Generating job metadata...")
    metadata = generator.generate_job_metadata(
        template_obj=template_obj,
        slurm_config=slurm_config,
        uploaded_files=uploaded_files,
        job_name='test_pytorch_training'
    )
    print(f"✓ Metadata generated:")
    for key, value in metadata.items():
        if isinstance(value, dict):
            print(f"  {key}:")
            for k, v in value.items():
                print(f"    {k}: {v}")
        else:
            print(f"  {key}: {value}")
    print()

    print("=" * 80)
    print("✓ Test completed successfully!")
    print("=" * 80)


if __name__ == '__main__':
    test_script_generation()
