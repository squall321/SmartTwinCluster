import React from 'react';
interface StreamRunnerProps {
    solver: string | null;
    mode: string | null;
    txtFiles?: File[];
    optFiles?: File[];
    autoSubmit?: boolean;
}
declare const StreamRunner: React.FC<StreamRunnerProps>;
export default StreamRunner;
