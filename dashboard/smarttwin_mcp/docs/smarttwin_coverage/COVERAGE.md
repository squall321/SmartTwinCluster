<!-- 생성됨: tools/_gen/generate_smarttwin_tools.py — SmartTwin 기능 ↔ MCP/REST 도구 대응표 -->
# SmartTwin 기능 커버리지

정본 pyKooCAE `380027d` · 후처리 `/data/SmartTwinPostprocessor/bin` 기준. 기능 128개 → 도구 126개.

| 제품 | 분류 | 기능 | MCP 도구 (REST: POST /smarttwin-api/v1/tools/<도구>/run) | 요약 |
|---|---|---|---|---|
| KooMeshModifier | 낙하·충격 | DROP_ATTITUDE | `kmm_drop_attitude` | 제품 낙하 해석 덱 생성 — 자세(오일러각)·높이·바닥판·접촉 자동 구성 |
| KooMeshModifier | 낙하·충격 | DROP_WEIGHT_IMPACT_TEST | `kmm_drop_weight_impact_test` | 낙추(충격추) 시험 덱 — 구·다단 실린더 충격추를 모델 위 지점에 떨어뜨림 |
| KooMeshModifier | 하중 | VIBRATION_LOAD | `kmm_vibration_load` | 진동 하중 — 하중곡선 × 파트별 계수로 LOAD_BODY/LOAD_NODE 생성 |
| KooMeshModifier | 하중 | THERMAL_LOAD | `kmm_thermal_load` | 열 하중 — 균일 온도 변화 열응력 또는 IC 발열(ICPower) 2-pass |
| KooMeshModifier | 파트·재료 | ELASTIC_TO_RIGID | `kmm_elastic_to_rigid` | 모든 변형체 파트를 강체(MAT_RIGID)로 — 지정 PID 만 제외 |
| KooMeshModifier | 파트·재료 | MATERIAL_EXCHANGE | `kmm_material_exchange` | 재료 카드 치환 + 변수 스윕 — 값 목록마다 .k 한 개씩 |
| KooMeshModifier | 파트·재료 | PART_EXCHANGE | `kmm_part_exchange` | 파트의 재료·단면·요소 형식 교체 (솔리드→TShell, 비정렬→정렬 격자 등) |
| KooMeshModifier | 파트·재료 | PART_MORPHING | `kmm_part_morphing` | 파트 형상 국부 변형 — 박스/파트 영역을 밀거나 당김 |
| KooMeshModifier | 파트·재료 | WARPED_PART | `kmm_warped_part` | 워피지(휨) 측정 데이터를 파트 형상에 반영 |
| KooMeshModifier | 파트·재료 | WARPED_TO_INITIAL_STRESS_PART | `kmm_warped_to_initial_stress_part` | 워피지를 형상 대신 초기 응력으로 부여 |
| KooMeshModifier | 파트·재료 | DIMENSIONAL_TOLERANCE | `kmm_dimensional_tolerance` | 파트 치수 공차 DOE — 목록/정규분포/LHS 로 파트 크기 변형 케이스 생성 |
| KooMeshModifier | 메시 | RIGIDIFY_SMALL_DT | `kmm_rigidify_small_dt` | stable dt 가 작은 요소를 강체 파트로 분리하고 접촉에서 제외 |
| KooMeshModifier | 메시 | ERODING_MIN_DT | `kmm_eroding_min_dt` | 요소 삭제(erosion) 최소 dt 설정 — MAT_ADD_EROSION 류 |
| KooMeshModifier | 메시 | REMESH_TETRA | `kmm_remesh_tetra` | 지정 파트를 품질 좋은 사면체로 재메시 (공유 절점 유지) |
| KooMeshModifier | 메시 | DEFEATURE_MESH | `kmm_defeature_mesh` | 짧은 모서리(작은 형상) 제거로 메시 단순화 |
| KooMeshModifier | 메시 | COHESIVE_BETWEEN_CONFORMAL_MESHES | `kmm_cohesive_between_conformal_meshes` | 절점 공유 두 파트 사이에 코히시브 요소층 삽입 |
| KooMeshModifier | 메시 | CONSTRAINED_NODAL_RIGIDBODY_TO_BEAM | `kmm_constrained_nodal_rigidbody_to_beam` | CNRB(절점 강체) 연결을 빔 요소로 치환 |
| KooMeshModifier | 메시 | CONVERT_CNRB_TO_SOLID | `kmm_convert_cnrb_to_solid` | 원통 배치 CNRB(나사 등)를 솔리드 원통으로 치환 |
| KooMeshModifier | 메시 | FEM_TO_IGA | `kmm_fem_to_iga` | FEM 파트를 IGA(NURBS) 파트로 변환 |
| KooMeshModifier | 접촉·검증 | CONTACT_AUTO_DECOMPOSITION | `kmm_contact_auto_decomposition` | 큰 접촉을 근접 파트 쌍 접촉으로 자동 분해 |
| KooMeshModifier | 접촉·검증 | REMOVE_DUPLICATE_TIED_CONTACTS | `kmm_remove_duplicate_tied_contacts` | 같은 면을 중복으로 묶은 TIED 접촉 제거 |
| KooMeshModifier | 접촉·검증 | WEAK_COUPLING | `kmm_weak_coupling` | 전체 모델 결과(d3plot) 경계 변위로 부분 모델 구동 (서브모델링) |
| KooMeshModifier | 접촉·검증 | PART_VALIDATION_SPLIT | `kmm_part_validation_split` | 파트별 독립 .k 분할 + 0° 낙하 검증 모델 일괄 생성 |
| KooMeshModifier | DOE·변환 | TRANSFORM | `kmm_transform` | 모델 전체 이동·회전·스케일·미러 |
| KooMeshModifier | DOE·변환 | PART_TRANSLATE | `kmm_part_translate` | 특정 파트만 이동 (이동 유지 — 뒤 모드가 이동된 형상 사용) |
| KooMeshModifier | DOE·변환 | TRANSLATION_DOE | `kmm_translation_doe` | 파트 위치 DOE — 파트별 이동량 목록마다 .k 한 개씩 (원복) |
| KooMeshModifier | DOE·변환 | PART_LOCATION_DOE | `kmm_part_location_doe` | 파트 배치 DOE — 마스크 파트 안 격자/샘플 위치에 파트 배치 |
| KooMeshModifier | k 파일 | DECOMPOSE_K | `kmm_decompose_k` | 모델을 그룹별 include 파일 세트로 분해 (master.k + groups/*.k) |
| KooMeshModifier | k 파일 | MERGE_K | `kmm_merge_k` | *INCLUDE 로 나뉜 모델을 한 .k 로 합침 |
| KooMeshModifier | k 파일 | IMPORT_MERGE_K | `kmm_import_merge_k` | 다른 .k 파일을 불러와 ID 충돌 없이 현재 모델에 합침 |
| KooMeshModifier | k 파일 | DYNAIN_TO_INITIAL | `kmm_dynain_to_initial` | 이전 해석 dynain(변형 형상+응력)을 다음 해석 초기 상태로 |
| KooMeshModifier | 자동화 | SIMULATION_AUTOMATION | `kmm_simulation_automation` | 시나리오 JSON 으로 여러 해석 모델을 일괄 생성 |
| KooMeshModifier | 체인 | chain | `kmm_chain` | 여러 모드를 한 옵션 파일에 순서대로 |
| KooAutomatedModeller | 패키지·부품 | PKG | `kam_pkg` | 적층(Layer) 정의 텍스트로 반도체 패키지 형상(STEP) 또는 LS-DYNA 메시(.k) 생성 |
| KooAutomatedModeller | 패키지·부품 | CAPACITOR | `kam_capacitor` | MLCC 칩 커패시터(패드·터미널·솔더·유전체 적층) 형상과 메시 생성 |
| KooAutomatedModeller | PCB·PBA | PCB | `kam_pcb` | ODB++ 추출 피처로 다층 PCB 형상(STEP) 생성 |
| KooAutomatedModeller | PCB·PBA | ArrayPCB | `kam_arraypcb` | 어레이(판넬) PCB 형상 생성 — *PCB 와 같은 키, 워피지 파일 지원 |
| KooAutomatedModeller | PCB·PBA | PBA | `kam_pba` | ODB++ 압축파일(.zip/.tgz)에서 PCB + 부품 실장 보드(PBA) 전체 형상 생성 |
| KooAutomatedModeller | 메시 | AIRMESH | `kam_airmesh` | STEP 솔리드 주변 공기 영역을 경계 추종 사면체로 채우고 STL 스킨 추출 |
| KooRemapper | analysis | ale | `remap_ale` | LS-DYNA 파트를 ALE(임의 라그랑-오일러) 형식으로 변환, 물성 프리셋 및 FSI 커플링 적용 |
| KooRemapper | deform | applyfold | `remap_applyfold` | linkage-fit 이 적은 군별 변환을 덱에 찍기 — 빠지는 절점이 하나도 없어야 한다. |
| KooRemapper | deform | assemble | `remap_assemble` | Assemble a full model with sequential part operations (replace, squeeze, restack |
| KooRemapper | analysis | battery | `remap_battery` | Generate LS-DYNA battery cell model (stacked/wound, Phase 1+2, swelling support) |
| KooRemapper | deform | bend | `remap_bend` | Apply bending deformation and optional prestress to a part. |
| KooRemapper | bc | boundary | `remap_boundary` | Apply boundary conditions (SPC/rigid wall) from YAML config |
| KooRemapper | deform | cclip | `remap_cclip` | Replace hex box parts with F-δ calibrated C-clip shell strips (smartphone spring |
| KooRemapper | mesh | cleanup-nodes | `remap_cleanup_nodes` | Report (default) or delete nodes that nothing in the deck references, reading ea |
| KooRemapper | mesh | cnrb2solid | `remap_cnrb2solid` | CNRB 강체 볼트를 O-grid HEX8 원형 솔리드 메시로 변환 |
| KooRemapper | bc | cnrb2spring | `remap_cnrb2spring` | CNRB 체결점을 두 강체 + 유격 discrete beam 조인트로 분할 |
| KooRemapper | bc | contact | `remap_contact` | Analyze, create, modify, convert, remove, or auto-detect contact definitions (*C |
| KooRemapper | mesh | convert | `remap_convert` | 선형 요소를 2차 요소로 변환 (TET10/HEX20/QUAD8/TRIA6) |
| KooRemapper | analysis | database | `remap_database` | Insert DATABASE output control keywords into K-file with presets or custom setti |
| KooRemapper | mesh | disconnect | `remap_disconnect` | Decohere conformal mesh interface for fracture modeling by splitting shared node |
| KooRemapper | mesh | elform | `remap_elform` | Change element formulation (ELFORM) in LS-DYNA *SECTION_* cards |
| KooRemapper | analysis | explicit | `remap_explicit` | LS-DYNA K-file에서 implicit/DR/modal 키워드를 제거하여 순수 explicit 형태로 변환 |
| KooRemapper | mesh | extract-parts | `remap_extract_parts` | Write a deck holding only the chosen parts, keeping every ID, the deck's field w |
| KooRemapper | mesh | extract-surface | `remap_extract_surface` | Extract free surface faces from solid HEX8/TET4 mesh as ELEMENT_SHELL (QUAD4) |
| KooRemapper | deform | foldsurface | `remap_foldsurface` | 접힘 곡면(평면 elastica) 중심선 — 최소 곡률반경을 목표로 고정하고 B 를 푼다. |
| KooRemapper | deform | formstrain | `remap_formstrain` | Compute plastic strain from shell mesh dihedral angles using curvature estimatio |
| KooRemapper | core | generate | `remap_generate` | Generate example test meshes (curved/bent types or box solids) with customizable |
| KooRemapper | core | generate-var | `remap_generate_var` | YAML 설정으로부터 평탄 또는 곡선 가변 밀도 메시 생성 |
| KooRemapper | bc | hfdamp | `remap_hfdamp` | LS-DYNA *DAMPING_FREQUENCY_RANGE_DEFORM 키워드 삽입으로 고주파 노이즈 감쇠 |
| KooRemapper | mesh | iga | `remap_iga` | Embed FE parts in IGA (Isogeometric Analysis) NURBS trivariate box |
| KooRemapper | analysis | implicit | `remap_implicit` | LS-DYNA explicit K-file을 implicit 솔버 세팅으로 변환하며, 명시적 전용 카드 제거 및 CONTROL_IMPLICIT_ |
| KooRemapper | deform | indent | `remap_indent` | Apply indentation or embossing deformation and compute prestress with polygon or |
| KooRemapper | core | info | `remap_info` | Display comprehensive mesh information including node/element counts, bounding b |
| KooRemapper | analysis | linkage-fit | `remap_linkage_fit` | 접힌 덱에서 군별 강체변환(축·각·피벗·축이동) 역산 — 피벗 산포를 함께 보고. |
| KooRemapper | bc | load | `remap_load` | YAML으로 부하(압력/힘)를 부분에 적용하고 *LOAD_*, *DEFINE_CURVE, *SET_* 키워드 삽입 |
| KooRemapper | core | map | `remap_map` | Map a flat unstructured mesh onto a bent structured mesh |
| KooRemapper | material | matdb | `remap_matdb` | Replace *MAT cards from a JSON material database with structural and thermal car |
| KooRemapper | material | matswap | `remap_matswap` | Replace material bundle (MAT/HOURGLASS/DEFINE_CURVE/SECTION) for one or more par |
| KooRemapper | mesh | merge | `remap_merge` | Merge multiple stacked solid layers into homogenized layer with Voigt/Reuss/VRH  |
| KooRemapper | mesh | meshfix | `remap_meshfix` | TET4 Gmsh-based adaptive remesh with quality control |
| KooRemapper | analysis | modal | `remap_modal` | Convert explicit LS-DYNA K-file for implicit modal (eigenvalue) analysis |
| KooRemapper | inspect | modelmeta | `remap_modelmeta` | Extract structured model metadata JSON — per-part free-surface area, volume, x/y |
| KooRemapper | inspect | neutralaxis | `remap_neutralaxis` | 적층 단면의 EI 가중 중립축·굽힘강성 계산 (읽기 전용 보고). |
| KooRemapper | mesh | offset | `remap_offset` | Extrude surface elements to solid HEX8 layer(s) with optional tied/CZM/contact c |
| KooRemapper | analysis | optimize | `remap_optimize` | Apply material-specific global card optimization for rubber/foam analysis in LS- |
| KooRemapper | deform | prestress | `remap_prestress` | 변형 메시로부터 초기응력(초기변형률) 계산 및 dynain 출력. |
| KooRemapper | bc | rbe | `remap_rbe` | RBE2/RBE3 rigid body element constraints from YAML config |
| KooRemapper | mesh | refine | `remap_refine` | Mesh refinement by subdivision (1:2 or 1:3 split) |
| KooRemapper | mesh | refshell | `remap_refshell` | 2D 곡선을 폭 방향으로 쓸어 QUAD4 기준 셸 덱 생성 (shellmap 의 기준면). |
| KooRemapper | analysis | relax | `remap_relax` | Set up Dynamic Relaxation for initial stress equilibrium with 5-level preset sys |
| KooRemapper | mesh | restack | `remap_restack` | Re-divide an extruded solid part into stacked layers, each with its own thicknes |
| KooRemapper | inspect | section | `remap_section` | 메시를 평면으로 잘라 요소 다각형 + 매니페스트를 낸다 (그림의 엔진). |
| KooRemapper | core | shellmap | `remap_shellmap` | Map a flat detail mesh onto a bent QUAD4 shell reference mesh |
| KooRemapper | deform | squeeze | `remap_squeeze` | Compress parts with strain conditions and generate initial stress/strain for int |
| KooRemapper | analysis | stabilize | `remap_stabilize` | LS-DYNA explicit solver 안정화 제어 (12단계 누적 시스템) |
| KooRemapper | inspect | stackdiagram | `remap_stackdiagram` | 파트별 축 범위로 층 모식도를 그리고 중립축·기하 중심면을 함께 긋는다 (포개지는 적층은 거절한다). |
| KooRemapper | deform | stackwrap | `remap_stackwrap` | 적층을 EI 중립축 기준으로 옮겨 기준 셸에 감기 (shellmap 의 z=0 전제를 맞춘다). |
| KooRemapper | deform | strain | `remap_strain` | Calculate strain tensor between reference and deformed meshes |
| KooRemapper | mesh | strip | `remap_strip` | Remove specified LS-DYNA keyword blocks from a K-file for debugging and comparis |
| KooRemapper | inspect | surfview | `remap_surfview` | 자유면만 뽑아 직교투영·깊이정렬로 그린다 (전체 와이어프레임은 검은 덩어리가 된다). |
| KooRemapper | mesh | tetremesh | `remap_tetremesh` | TET4 local remesh: improve quality via Laplacian smoothing/swap (localimprove) o |
| KooRemapper | core | unfold | `remap_unfold` | Generate a flat unfolded mesh from a bent structured HEX8 mesh by computing arc- |
| KooRemapper | mesh | update | `remap_update` | Update node coordinates from a dynain or K-file with *NODE block. |
| KooRemapper | deform | warpage | `remap_warpage` | 측정된 변형 데이터를 셸 또는 솔리드 부품에 적용합니다 |
| KooRemapper | mesh | wrap | `remap_wrap` | Apply winding tension prestress (hoop + radial stress) for cylindrical parts |
| SmartTwinPostprocessor | 후처리 | post_analyze | `post_analyze` | 통합 후처리 — unified_analyzer → sphere/impact report → deep report (기존 결과 자동 스킵) |
| SmartTwinPostprocessor | 후처리 | unified_analyzer | `post_unified_analyzer` | d3plot 분석 엔진 — YAML 작업(응력·변형률·운동·표면·핫스팟·렌더) 단일/재귀 실행 |
| SmartTwinPostprocessor | 후처리 | koo_deep_report | `post_deep_report` | 단일 시뮬 깊은 분석 HTML 리포트 — 파트별 응력·변형률·핫스팟 군집·단면뷰 |
| SmartTwinPostprocessor | 후처리 | koo_sphere_report | `post_sphere_report` | 전각도 낙하 통합 리포트 — Mollweide 구면 지도·방향별 위험도 (또는 --from-json 재생성) |
| SmartTwinPostprocessor | 후처리 | koo_impact_report | `post_impact_report` | 부분충격(DWI) 다면 DOE 리포트 — 면별 위치 격자 위험도 (또는 --from-json 재생성) |
| SmartTwinPostprocessor | 후처리 | koo_federate_report | `post_federate_report` | 여러 리비전 sidecar(impact/sphere)를 하나의 비교 리포트로 연합 |
| SmartTwinPostprocessor | 후처리 | koo_custom_report | `post_custom_report` | *SET_ 정의 기반 커스텀 후처리 리포트 — 세트별 응력·변형률·영상 |
| SmartTwinPostprocessor | 후처리 | koo_scatter_report | `post_scatter_report` | 각도 산포 캠페인 리포트 — 편차각 산포·방향도·회수율 |
| SmartTwinPostprocessor | 후처리 | koo_dyna_diag | `post_dyna_diag` | LS-DYNA 결과 진단 — 에러·경고·성능 프로파일 JSON/HTML (단일 폴더 또는 일괄 색인) |
| SmartTwinPostprocessor | 후처리 | make_stl | `post_make_stl` | d3plot·모델 .k 에서 미리보기 STL 생성 (리포트 실형상 미리보기용) |
| KooChainRun | 시나리오 모드 | DROP | `scenario_drop` | 낙하 시나리오 — 자세 DOE(피보나치·육면체·스윕) × 누적 스텝 |
| KooChainRun | 시나리오 모드 | IMPACT | `scenario_impact` | 충격 시나리오 — 모델 윗면 격자 위치마다 구·다단 실린더 충격추 낙하 |
| KooChainRun | 시나리오 모드 | VIBRATION | `scenario_vibration` | 진동 시나리오 — 하중 곡선 × 파트 계수 (명시·캡별·회로별 DOE) |
| KooChainRun | 시나리오 모드 | THERM | `scenario_therm` | 열 시나리오 — 균일 챔버 온도 열응력 또는 IC 발열 2-pass |
| KooChainRun | 시나리오 모드 | REMAP | `scenario_remap` | 누적 스텝 사이에 KooRemapper 변환(재질 교체 등)을 끼우는 러너 전용 스텝 |
| KooChainRun | 워크플로우 (최상위 mode) | part_validation | `scenario_part_validation` | 파트별 0° 낙하 검증 — 파트마다 독립 .k 로 쪼개 해석 가능 여부 사전 점검 |
| KooChainRun | 워크플로우 (최상위 mode) | drop_weight_impact | `scenario_drop_weight_impact` | (구) 전위치 부분충격 워크플로우 — IMPACT 시나리오와 별도 스키마 |
| KooChainRun | 범용 | scenario.json | `scenario_submit` | 임의 scenario.json 제출 |
| KooChainRun | 명령 | prepare | `scenario_submit` | scenario.json → runner_config.json |
| KooChainRun | 명령 | submit | `scenario_submit` | Slurm 제출 |
| KooChainRun | 명령 | status | `job_status` | 진행 상황 |
| KooChainRun | 명령 | collect | `job_collect` | 결과 수집 |
| KooChainRun | 명령 | postprocess | `job_postprocess` | 후처리 수동 실행 |
| KooChainRun | 명령 | diagnose | `job_diagnose` | 실패 원인 진단 |
| KooChainRun | 명령 | rerun | `job_rerun` | 실패·미완료 재실행 |
| KooChainRun | 명령 | stop | `job_stop` | 잡 전부 취소 |
| KooChainRun | 명령 | reprioritize | `job_reprioritize` | 대기 잡 우선순위 재배치 |
| KooChainRun | 명령 | harvest | `job_harvest` | 취약 조건 JSON 추출 |
| KooChainRun | 원클릭 | fullangle_drop_simulation | `fullangle_drop_simulation` | 전각도 낙하 원클릭 — 모델 하나로 피보나치 N 방향 낙하 + 자동 후처리 |
| KooChainRun | 원클릭 | single_drop_simulation | `single_drop_simulation` | 지정 각도(roll/pitch/yaw) 1방향 낙하 원클릭 |
