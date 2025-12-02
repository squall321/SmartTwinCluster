import { jsx as _jsx } from "react/jsx-runtime";
// components/simulationnetwork/SearchFilter.tsx
import { useState, useEffect, useMemo } from 'react';
import { Input } from 'antd';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import debounce from 'lodash.debounce';
const { Search } = Input;
const SearchFilter = () => {
    const setSearchQuery = useSimulationNetworkStore(state => state.setSearchQuery);
    const [inputValue, setInputValue] = useState('');
    const debouncedSetQuery = useMemo(() => debounce((val) => setSearchQuery(val), 300), [setSearchQuery]);
    useEffect(() => () => debouncedSetQuery.cancel(), [debouncedSetQuery]);
    const onChange = (e) => {
        const { value } = e.target;
        setInputValue(value);
        debouncedSetQuery(value.trim());
    };
    return (_jsx(Search, { placeholder: "Search by Case ID or path", allowClear: true, value: inputValue, onChange: onChange, style: { width: 260 } }));
};
export default SearchFilter;
