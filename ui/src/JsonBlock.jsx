import { useState } from 'react';

export default function JsonBlock({ value }) {
  const [copied, setCopied] = useState(false);
  const text = JSON.stringify(value, null, 2);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    } catch {
      /* clipboard unavailable */
    }
  };

  return (
    <div className="json">
      <button type="button" className="copy" onClick={copy}>
        {copied ? 'copied' : 'copy'}
      </button>
      <pre>{text}</pre>
    </div>
  );
}
