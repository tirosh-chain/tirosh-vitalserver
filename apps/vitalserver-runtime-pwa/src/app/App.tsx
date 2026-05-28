import { NavLink, Route, Routes } from "react-router-dom";

import { runtimeControlRoutes } from "./routes";

export function App() {
  return (
    <div className="app-shell">
      <header className="app-header">
        <div>
          <h1>VitalServer Helper</h1>
          <p>Runtime Control</p>
        </div>
      </header>

      <nav className="app-tabs" aria-label="Runtime Control tabs">
        {runtimeControlRoutes.map((route) => (
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
          {runtimeControlRoutes.map(({ path, Page }) => (
            <Route key={path} path={path} element={<Page />} />
          ))}
        </Routes>
      </main>
    </div>
  );
}
