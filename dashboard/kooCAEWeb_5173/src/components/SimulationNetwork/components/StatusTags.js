import { jsx as _jsx, Fragment as _Fragment } from "react/jsx-runtime";
import { Tag } from 'antd';
import { getStatusColor } from '../utils/statusUtils';
const StatusTags = ({ statuses }) => (_jsx(_Fragment, { children: statuses.map(s => _jsx(Tag, { color: getStatusColor(s), children: s }, s)) }));
export default StatusTags;
