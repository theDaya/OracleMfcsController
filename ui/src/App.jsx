import { useCallback, useEffect, useState } from 'react';
import { getMasterData, getReferenceData, getTokenStatus } from './api';
import { initialForm } from './formState';
import TransactionsTab from './TransactionsTab';
import BrowseTab from './BrowseTab';
import MasterDataTab from './MasterDataTab';
import SpecViewer from './SpecViewer';

const TABS = [
  { id: 'transactions', label: 'Transactions', hint: 'Build, preview and submit a request' },
  { id: 'browse', label: 'Browse', hint: 'Existing styles and orders in MFCS' },
  { id: 'master', label: 'Master data', hint: 'Cached foundation data' },
  { id: 'spec', label: 'MFCS spec', hint: 'The tenant OpenAPI contract' },
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
    </div>
  );
}
