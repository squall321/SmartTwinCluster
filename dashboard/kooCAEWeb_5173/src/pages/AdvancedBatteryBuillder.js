import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Button, Divider, Typography, Space, message, InputNumber } from 'antd';
import PartSelector from '../components/shared/PartSelector';
import { useNavigate } from 'react-router-dom';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import { DownloadOutlined, PictureOutlined } from '@ant-design/icons';
import CuboidNetPainter from '../components/CuboidNet/CuboidNetPainter';
const { Title, Paragraph, Text } = Typography;
const AdvancedBatteryBuilder = () => {
    const navigate = useNavigate();
    const [kFileName, setKFileName] = useState('uploaded_file.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [selectedParts, setSelectedParts] = useState([]);
    const [uploadedKFile, setUploadedKFile] = useState(null);
    // ✅ 추가: 하위에서 받은 6면 이미지 파일 저장
    const [faceImages, setFaceImages] = useState(null);
    const painterRef = useRef(null);
    const [faceFiles, setFaceFiles] = useState(null);
    const [thickness, setThickness] = useState(0.1);
    // 공용 다운로드 헬퍼
    function downloadBlob(filename, blob) {
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        // 약간 뒤에 revoke하면 안전
        setTimeout(() => URL.revokeObjectURL(link.href), 1000);
    }
    const handlePartSelect = (part) => {
        const index = selectedParts.findIndex((p) => p.id === part.id);
        const updated = [...selectedParts];
        if (index >= 0)
            updated[index] = part;
        else
            updated.push(part);
        setSelectedParts(updated);
    };
    const handleRemovePart = (id) => {
        setSelectedParts((prev) => prev.filter((p) => p.id !== id));
    };
    // ✅ 옵션 텍스트 생성에 PNG 파일명 매핑 추가
    const buildOptionText = (files) => {
        const lines = [];
        lines.push(`*Inputfile`);
        lines.push(`${kFileName}`);
        lines.push(`*Mode`);
        lines.push(`WRAPPING_PART,1`);
        lines.push(`**WrappingPart,1`);
        // PNG 매핑 섹션 (원하시면 키워드명 변경 가능: 예 *TapeImages)
        lines.push(`FaceImages`);
        // 파일명이 존재하면 파일명, 없으면 경고 주석
        const add = (label, file) => {
            if (file)
                lines.push(`${label},${file.name}`);
            else
                lines.push(`# ${label},(missing)`);
        };
        if (!files)
            return lines.join('\n'); // 파일이 없으면 그냥 종료
        add('px', files?.box_px);
        add('mx', files?.box_mx);
        add('py', files?.box_py);
        add('my', files?.box_my);
        add('pz', files?.box_pz);
        add('mz', files?.box_mz);
        lines.push(`Thickness,${thickness}`);
        lines.push('**EndWrappingPart');
        lines.push(`*End`);
        return lines.join('\n');
    };
    const exportScript = async () => {
        // 1) faceFiles 없으면 먼저 생성
        let files = faceFiles;
        if (!files) {
            files = await painterRef.current?.exportFaces() ?? null;
            if (files)
                setFaceFiles(files); // 상태도 업데이트
        }
        // 2) 옵션 텍스트 다운로드
        const text = buildOptionText(files ?? undefined);
        const txtBlob = new Blob([text], { type: 'text/plain;charset=utf-8' });
        downloadBlob('advancedBatteryBuilder.txt', txtBlob);
        // 3) 6면 PNG 모두 다운로드 (files가 있다면)
        if (files) {
            // 파일 이름 고정으로 받고 싶으면 files의 key를 이름으로 사용
            // (File 객체에 이미 name이 있으니 그대로 써도 됨)
            const orderedKeys = [
                'box_px', 'box_mx', 'box_py', 'box_my', 'box_pz', 'box_mz'
            ];
            for (const k of orderedKeys) {
                const f = files[k];
                // File 그대로 다운로드
                downloadBlob(f.name || `${k}.png`, f);
            }
        }
        else {
            console.warn('faceFiles 생성에 실패했습니다.');
        }
    };
    // ✅ 추가: 6면 PNG 개별/일괄 다운로드
    const downloadFacePNGs = () => {
        if (!faceImages) {
            message.warning('먼저 6면 이미지를 생성해서 받아오세요.');
            return;
        }
        const entries = Object.entries(faceImages);
        entries.forEach(([key, file]) => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(file);
            a.download = file.name || `${key}.png`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
        });
    };
    // 공통 헬퍼: faceImages 없으면 생성
    async function ensureFaceImages() {
        if (faceImages)
            return faceImages;
        const files = await painterRef.current?.exportFaces();
        if (!files)
            throw new Error("Failed to export faces from painter");
        setFaceImages(files);
        return files;
    }
    // ✅ MeshModifier 실행 시 이미지 파일도 함께 전달
    const runMeshModifier = async () => {
        try {
            // 0) 먼저 6면 PNG 확보 (없으면 생성)
            const faces = await ensureFaceImages();
            // 1) 옵션 텍스트 파일
            const text = buildOptionText();
            const optionFile = new File([text], "advancedBatteryBuilder.txt", { type: "text/plain" });
            // 2) K 파일
            const kFile = uploadedKFile;
            // 3) 이미지 배열 (이름을 표준화해서 넘기면 수신부에서 다루기 편해요)
            const ordered = ["box_px", "box_mx", "box_py", "box_my", "box_pz", "box_mz"];
            const imageFiles = ordered.map(k => {
                const f = faces[k];
                // 이름 통일 (수신부가 파일명으로 매핑할 때 유리)
                return new File([f], `${k}.png`, { type: "image/png" });
            });
            // 4) StreamRunner로 전달
            navigate("/tools/stream-runner", {
                state: {
                    solver: "MeshModifier",
                    mode: "AdvancedBattery",
                    txtFiles: [optionFile], // 옵션/스크립트류
                    optFiles: kFile ? [kFile] : [], // K 파일 (입력 메쉬)
                    binFiles: imageFiles, // ⬅️ PNG 6개
                    autoSubmit: true,
                },
            });
        }
        catch (error) {
            console.error("Mesh Modifier 실행 중 오류가 발생했습니다.", error);
            message.error("Mesh Modifier 실행 중 오류가 발생했습니다.");
        }
    };
    // ✅ CuboidNetPainter에서 6면 파일을 받는 핸들러
    const handleExportFaces = (images) => {
        setFaceFiles(images);
        message.success('6면 PNG 파일을 받았습니다.');
    };
    // ✅ “파일이 없으면 자식에게 exportFaces를 호출”
    useEffect(() => {
        if (!faceFiles) {
            // 렌더가 안정된 다음 한 번만 시도
            const id = requestAnimationFrame(async () => {
                try {
                    const files = await painterRef.current?.exportFaces();
                    if (files)
                        setFaceFiles(files);
                }
                catch (e) {
                    console.error(e);
                }
            });
            return () => cancelAnimationFrame(id);
        }
    }, [faceFiles]);
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Advanced Battery Builder" }), _jsx(Paragraph, { children: "K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0 Battery Part ID\uB97C \uC120\uD0DD\uD55C \uB4A4 Wrapping Tape \uD328\uD134\uC744 \uC801\uC6A9\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                        setKFileName(filename);
                        setAllPartInfos(parts);
                        setSelectedParts([]);
                        setUploadedKFile(file ?? null);
                    } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(Divider, {}), _jsx(CuboidNetPainter, { ref: painterRef, onExportFaces: handleExportFaces }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Thickness" }), _jsx(InputNumber, { value: thickness, onChange: (value) => setThickness(Number(value ?? 0.1)) }), _jsx(Divider, {}), _jsx("div", { style: { marginTop: '2rem', textAlign: 'center' }, children: _jsxs(Space, { wrap: true, children: [_jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), onClick: async () => {
                                    // faceFiles 없으면 먼저 생성
                                    if (!faceFiles) {
                                        const files = await painterRef.current?.exportFaces();
                                        if (files)
                                            setFaceFiles(files);
                                    }
                                    // faceFiles 준비된 뒤 실행
                                    exportScript();
                                }, children: "\uC635\uC158\uD30C\uC77C \uCD9C\uB825" }), _jsx(Button, { icon: _jsx(PictureOutlined, {}), onClick: downloadFacePNGs, disabled: !faceFiles, children: "6\uBA74 PNG \uB2E4\uC6B4\uB85C\uB4DC" }), _jsx(Button, { style: { marginLeft: 12 }, onClick: async () => {
                                    // faceFiles 없으면 먼저 생성
                                    if (!faceFiles) {
                                        const files = await painterRef.current?.exportFaces();
                                        if (files)
                                            setFaceFiles(files);
                                    }
                                    // faceFiles 준비된 뒤 실행
                                    runMeshModifier();
                                }, children: "\uD83D\uDD01 \uD574\uC11D \uC2E4\uD589 (Mesh Modifier)" })] }) })] }) }));
};
export default AdvancedBatteryBuilder;
