import { frontendURL } from '../../../helper/URLHelper';
import Overview from './pages/Overview.vue';
import TestWidget from './pages/TestWidget.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/converttrack/overview'),
    name: 'converttrack_overview_index',
    component: Overview,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/converttrack/test'),
    name: 'converttrack_test_index',
    component: TestWidget,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/converttrack'),
    redirect: to => ({
      name: 'converttrack_overview_index',
      params: to.params,
    }),
  },
];
