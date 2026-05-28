import { Navigate, NavLink, Route, Routes } from "react-router-dom";

import { useRuntimeCapabilities } from "../application/runtime-control/queries";
import { runtimeControlRoutes } from "./routes";

export function App() {
  const capabilities = useRuntimeCapabilities();
  const canUseTestTools = capabilities.data?.canUseTestTools === true;
  const visibleRoutes = runtimeControlRoutes.filter(
    (route) => !route.requiresTestTools || canUseTestTools
  );

  return (
    <div className="app-shell">
      <header className="app-header">
        <div>
          <h1>VitalServer Helper</h1>
          <p>Runtime Control</p>
        </div>
      </header>

      <nav className="app-tabs" aria-label="Runtime Control tabs">
        {visibleRoutes.map((route) => (
          <NavLink
            key={route.path}
            to={route.path}
            end={route.path === "/"}
            className={({ isActive }) =>
              isActive ? "app-tab app-tab-active" : "app-tab"
            }
          >
            {route.label}
          </NavLink>
        ))}
      </nav>

      <main className="app-main">
        <Routes>
          {visibleRoutes.map(({ path, Page }) => (
            <Route key={path} path={path} element={<Page />} />
          ))}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}
