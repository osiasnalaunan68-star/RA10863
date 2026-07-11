const API_BASE = "";
export async function searchCMTA(query, filter) {
  const res = await fetch(`${API_BASE}/api/search?q=${encodeURIComponent(query)}&filter=${filter}`);
  return res.json();
}
