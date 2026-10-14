import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import "./index.css";
import Dashboard from "./pages/Dashboard";
import ScanDetail from "./pages/ScanDetail";
import Osint from "./pages/Osint";
import Plugins from "./pages/Plugins";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/scans/:id" element={<ScanDetail />} />
        <Route path="/osint" element={<Osint />} />
        <Route path="/plugins" element={<Plugins />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>
);
