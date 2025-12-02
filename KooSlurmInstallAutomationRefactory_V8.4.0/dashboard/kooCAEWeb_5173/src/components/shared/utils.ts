import { ParsedPart } from '../../types/parsedPart';

export function generateRigidOptionFile(
  filename: string,
  allParts: ParsedPart[],
  excludedParts: ParsedPart[]
): File {
  const content = generateRigidOptionText(filename, allParts, excludedParts);
  return new File([content], 'elasticToRigidOption.txt', { type: 'text/plain' });
}
export function generateRigidOptionText(
    filename: string,
    allParts: ParsedPart[],
    excludedParts: ParsedPart[]
  ): string {
    const modeId = 1;
    const excludedIds = excludedParts.map(p => p.id);
    const allIds = allParts.map(p => p.id);
    const includedIds = allIds.filter(id => !excludedIds.includes(id));
  
    const lines: string[] = [];
    lines.push(`*Inputfile`);
    lines.push(`${filename}`);
    lines.push(`*Mode`);
    lines.push(`ELASTIC_TO_RIGID,${modeId}`);
    lines.push(`**ElastictoRigid,${modeId}`);
    lines.push(`*PIDExcept,${excludedIds.join(',')}`);
    lines.push(`**EndElastictoRigid`);
    lines.push(`*End`);
  
    return lines.join('\n');
  }
  
  export function generateDropAttitudeOptionFile(
    kFileName: string,
    tableData: any[],
    options: Record<string, number>
  ): File {
    const fields = Object.keys(tableData[0] ?? {});
    let content = '*Inputfile\n';
    content += `${kFileName || 'UNKNOWN.k'}\n`;
    content += '*Mode\n';
    content += 'DROP_ATTITUDE,1\n';
    content += '**DropAttitude,1\n';
  
    fields.forEach(field => {
      content += field + ',' + tableData.map(row => row[field]).join(',') + '\n';
    });
  
    Object.entries(options).forEach(([key, value]) => {
      content += `${key},${value}\n`;
    });
  
    content += '**EndDropAttitude\n*End';
  
    return new File([content], 'drop_attitude.txt', { type: 'text/plain' });
  }
  
export function generateDropWeightImpactTestOptionFile(
  kFileName: string,
  locationXList: number[],
  locationYList: number[],
  initialVelocityXList: number[],
  initialVelocityYList: number[],
  initialVelocityZList: number[],
  heightList: number[],
  tFinal: number,
  youngModulusDamper: number,
  poissonRatioDamper: number,
  density: number,
  youngModulus: number,
  densityDamper: number,
  poissonRatio: number,
  type: string,
  dimensionDamper: number[],
  meshSize: number,
  youngModulusFront: number,
  densityFront: number,
  poissonRatioFront: number,
  youngModulusWall: number,
  densityWall: number,
  poissonRatioWall: number,
  cylinderDimensions: number[],
  dimension: number[],
  offsetDistance: number
): File {
  let content = '*Inputfile\n';
  content += `${kFileName || 'UNKNOWN.k'}\n`;
  content += '*Mode\n';
  content += 'DROP_WEIGHT_IMPACT_TEST,1\n';
  content += '**DropWeightImpactTest,1\n';
  content += 'BoundaryDistance,0.0\n';
  content += `LocationX,${locationXList.join(',')}\n`;
  content += `LocationY,${locationYList.join(',')}\n`;
  content += `InitialVelocityX,${initialVelocityXList.join(',')}\n`;
  content += `InitialVelocityY,${initialVelocityYList.join(',')}\n`;
  content += `InitialVelocityZ,${initialVelocityZList.join(',')}\n`;
  content += `Height,${heightList.join(',')}\n`;
  content += `tFinal,${tFinal}\n`;
  content += `YoungModulusDamper,${youngModulusDamper}\n`;
  content += `PoissonRatioDamper,${poissonRatioDamper}\n`;
  content += `Density,${density}\n`;
  content += `YoungModulus,${youngModulus}\n`;
  content += `DensityDamper,${densityDamper}\n`;
  content += `PoissonRatio,${poissonRatio}\n`;
  content += `Type,${type}\n`;
  content += `DimensionDamper,${dimensionDamper.join(',')}\n`;
  content += `MeshSize,${meshSize}\n`;
  if (type === 'Cylinder') {
    content += `YoungModulusImpactorFront,${youngModulusFront}\n`;
    content += `DensityImpactorFront,${densityFront}\n`;
    content += `PoissonRatioImpactorFront,${poissonRatioFront}\n`;
    content += `YoungModulusWall,${youngModulusWall}\n`;
    content += `DensityWall,${densityWall}\n`;
    content += `PoissonRatioWall,${poissonRatioWall}\n`;
    content += `Dimension,${cylinderDimensions.join(',')}\n`;
  } else {
    content += `Dimension,${dimension}\n`;
  }
  content += `OffsetDistance,${offsetDistance}\n`;
  content += '**EndDropWeightImpactTest\n*End';
  return new File([content], 'drop_weight_impact_test.txt', { type: 'text/plain' });
}

export function generateDropWeightImpactTestbyPartsOptionFile(
  kFileName: string,
  partsIDs: number[],
  initialVelocityXList: number[],
  initialVelocityYList: number[],
  initialVelocityZList: number[],
  locationModes: string[],
  heightList: number[],
  tFinal: number,
  dt: number,
  density: number,
  youngModulus: number,
  poissonRatio: number,
  type: string,
  meshSize: number,
  youngModulusFront: number,
  densityFront: number,
  poissonRatioFront: number,
  youngModulusWall: number,
  densityWall: number,
  poissonRatioWall: number,
  cylinderDimensions: number[],
  dimension: number[],
  offsetDistance: number
): File{

  let content = '*Inputfile\n';
  content += `${kFileName || 'UNKNOWN.k'}\n`;
  content += `*Mode\n`;
  content += `DROP_WEIGHT_IMPACT_TEST,1\n`;
  content += `**DropWeightImpactTest,1\n`;
  content += `PartIDs,${partsIDs.join(',')}\n`;
  content += `InitialVelocityX,${initialVelocityXList.join(',')}\n`;
  content += `InitialVelocityY,${initialVelocityYList.join(',')}\n`;
  content += `InitialVelocityZ,${initialVelocityZList.join(',')}\n`;
  content += `LocationMode,${locationModes.join(',')}\n`;
  content += `Height,${heightList.join(',')}\n`;
  content += `tFinal,${tFinal}\n`;
  content += `dt,${dt}\n`;
  content += `Density,${density}\n`;
  content += `YoungModulus,${youngModulus}\n`;
  content += `PoissonRatio,${poissonRatio}\n`;
  content += `Type,${type}\n`;
  content += `MeshSize,${meshSize}\n`;
  if (type === 'Cylinder') {
    content += `YoungModulusImpactorFront,${youngModulusFront}\n`;
    content += `DensityImpactorFront,${densityFront}\n`;
    content += `PoissonRatioImpactorFront,${poissonRatioFront}\n`;
    content += `Dimension,${cylinderDimensions.join(',')}\n`;
  } else {
    content += `Dimension,${dimension}\n`;
  }
  content += `YoungModulusWall,${youngModulusWall}\n`;
  content += `DensityWall,${densityWall}\n`;
  content += `PoissonRatioWall,${poissonRatioWall}\n`;
    
  content += `OffsetDistance,${offsetDistance}\n`;
  content += `**EndDropWeightImpactTest\n*End`;
  return new File([content], 'drop_weight_impact_test_by_parts.txt', { type: 'text/plain' });

}

export function generateDimensionalToleranceOptionFile(
  kFileName: string,
  partsIDs: number[],
  directions: string[],
  variableMatrix: number[][]
): File { 

  let content = '*Inputfile\n';
  content += `${kFileName || 'UNKNOWN.k'}\n`;
  content += '*Mode\n';
  content += 'DIMENSIONAL_TOLERANCE,1\n';
  content += '**DimensionalTolerance,1\n';
  content += '*PartDimTolerance,LIST\n';
  for (let i = 0; i < partsIDs.length; i++) {
    content += `${partsIDs[i]},${directions[i]}`;
    for (let j = 0; j < variableMatrix[i].length; j++) {
      content += `,${variableMatrix[i][j]/100.0}`;
    }
    content += '\n';
  }
  content += '**EndDimensionalTolerance\n*End';

  return new File([content], 'dimensional_tolerance.txt', { type: 'text/plain' });
}