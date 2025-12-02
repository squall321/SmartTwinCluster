// components/simulationnetwork/SearchFilter.tsx
import React, { useState, useEffect, useMemo } from 'react';
import { Input } from 'antd';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import debounce from 'lodash.debounce';

const { Search } = Input;

const SearchFilter: React.FC = () => {
  const setSearchQuery = useSimulationNetworkStore(state => state.setSearchQuery);
  const [inputValue, setInputValue] = useState('');

  const debouncedSetQuery = useMemo(() => debounce((val: string) => setSearchQuery(val), 300), [setSearchQuery]);

  useEffect(() => () => debouncedSetQuery.cancel(), [debouncedSetQuery]);

  const onChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { value } = e.target;
    setInputValue(value);
    debouncedSetQuery(value.trim());
  };

  return (
    <Search
      placeholder="Search by Case ID or path"
      allowClear
      value={inputValue}
      onChange={onChange}
      style={{ width: 260 }}
    />
  );
};

export default SearchFilter;
