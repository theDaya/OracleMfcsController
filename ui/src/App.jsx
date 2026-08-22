import { useCallback, useEffect, useState } from 'react';
import { getMasterData, getReferenceData, getTokenStatus } from './api';
import { initialForm } from './formState';
import TransactionsTab from './TransactionsTab';
import BrowseTab from './BrowseTab';
import MasterDataTab from './MasterDataTab';
import SpecViewer from './SpecViewer';
import ActivityTab from './ActivityTab';
import FlowTab from './FlowTab';

// The console is a small MFCS hub: make things, watch what you made, look at what
// is already there, and check the contract you are working against.
const TABS = [
  { id: 'transactions', label: 'Build', hint: 'Create or modify a style or order, preview the calls, then submit' },
  { id: 'activity', label: 'Activity', hint: 'Transactions submitted from here, with their steps, attempts and errors' },
  { id: 'browse', label: 'Styles & orders', hint: 'What currently exists in MFCS' },
  { id: 'master', label: 'Master data', hint: 'Cached foundation data behind the dropdowns' },
  { id: 'spec', label: 'MFCS spec', hint: 'The tenant OpenAPI contract' },
  { id: 'flow', label: 'How it works', hint: 'The middleware end to end: operations, call paths, SKU logic, failure handling' },
];

export default function App() {
  const [tab, setTab] = useState('transactions');
  const [form, setForm] = useState(initialForm);
  const [reference, setReference] = useState(null);
  const [masterData, setMasterData] = useState(null);
  const [error, setError] = useState(null);
  const [token, setToken] = useState(null);

  const reloadMasterData = useCallback(
    () =>
      getMasterData()
        .then((r) => setMasterData(r.body))
        .catch((e) => setError(`Could not load master data: ${e.message}`)),
    [],
  );

  useEffect(() => {
    getReferenceData()
      .then((r) => setReference(r.body))
      .catch((e) => setError(`Could not load reference data: ${e.message}`));
    reloadMasterData();

    // Poll the token so an expiry shows up in the header rather than as
    // unexplained blank listings a few minutes later.
    const readToken = () => getTokenStatus().then((r) => setToken(r.body)).catch(() => {});
    readToken();
    const t = setInterval(readToken, 60000);
    return () => clearInterval(t);
  }, [reloadMasterData]);

  const runtime = reference?.runtime || {};
  const cachedCount = Object.values(masterData?.types || {}).reduce((n, v) => n + v.length, 0);

  return (
    <div className="app">
      <header>
        <div>
          <h1>Office MFCS Console</h1>
          <p className="sub">{TABS.find((t) => t.id === tab)?.hint}</p>
        </div>
        <div className="runtime">
          <span className="pill live" title={runtime.MFCS_BASE_URL}>
            LIVE MFCS
          </span>
          <span className="pill">{runtime.MFCS_AUTH_MODE || '…'}</span>
          {token && (
            <span
              className={`pill ${token.expired || !token.present ? 'bad' : 'ok'}`}
              title={token.message}
            >
              {!token.present
                ? 'no token'
                : token.expired
                  ? 'token expired'
                  : `token ${Math.round((token.secondsRemaining || 0) / 60)}m`}
            </span>
          )}
          {runtime.FEATURE_ITEM_LOCATIONS_YN === 'N' && <span className="pill off">locations off</span>}
          {runtime.FEATURE_INITIAL_RETAIL_YN === 'N' && <span className="pill off">initial retail off</span>}
        </div>
      </header>

      <nav className="toptabs">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            className={tab === t.id ? 'on' : ''}
            onClick={() => setTab(t.id)}
          >
            {t.label}
            {t.id === 'master' && cachedCount > 0 && <span className="count">{cachedCount}</span>}
          </button>
        ))}
      </nav>

      {error && <div className="banner error">{error}</div>}

      {tab === 'transactions' && (
        <TransactionsTab form={form} setForm={setForm} masterData={masterData} />
      )}

      {tab === 'activity' && <ActivityTab />}

      {tab === 'browse' && (
        <BrowseTab form={form} setForm={setForm} goToTransactions={() => setTab('transactions')} />
      )}

      {tab === 'master' && (
        <MasterDataTab masterData={masterData} reloadMasterData={reloadMasterData} />
      )}

      {tab === 'spec' && (
        <div className="panel">
          <SpecViewer usedEndpoints={reference?.endpoints} />
        </div>
      )}

      {tab === 'flow' && <FlowTab />}
    </div>
  );
}
