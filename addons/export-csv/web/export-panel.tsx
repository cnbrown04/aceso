import { useState } from "react";
import { get } from "../../../apps/web/src/lib/api";

export default function ExportPanel() {
  const [loading, setLoading] = useState(false);

  async function handleExport() {
    setLoading(true);
    const csv = await get<string>("/api/export/csv");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "aceso-export.csv";
    a.click();
    setLoading(false);
  }

  return (
    <button onClick={handleExport} disabled={loading}>
      {loading ? "Exporting…" : "Export CSV"}
    </button>
  );
}
