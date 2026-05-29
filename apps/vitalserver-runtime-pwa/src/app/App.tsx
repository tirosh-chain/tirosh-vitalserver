import { Navigate, NavLink, Route, Routes, useLocation } from "react-router-dom";

import { useRuntimeCapabilities } from "@/application/runtime-control/queries";
import { cn } from "@/shared/ui/cn";
import { runtimeControlRoutes, type RuntimeControlRoute } from "./routes";

export function App() {
  const capabilities = useRuntimeCapabilities();
  const location = useLocation();
  const canUseTestTools = capabilities.data?.canUseTestTools === true;
  const visibleRoutes = runtimeControlRoutes.filter(
    (route) => !route.requiresTestTools || canUseTestTools
  );
  const primaryRoutes = visibleRoutes.filter((route) => route.group === "primary");
  const utilityRoutes = visibleRoutes.filter((route) => route.group === "utility");
  const overflowRoutes = visibleRoutes.filter((route) => route.group === "overflow");
  const overflowActive = overflowRoutes.some((route) =>
    routeMatchesPath(route, location.pathname)
  );

  const routeLink = (
    route: RuntimeControlRoute,
    variant: "primary" | "utility" | "overflow"
  ) => (
    <NavLink
      key={route.path}
      to={route.path}
      end={route.path === "/"}
      className={({ isActive }) =>
        cn(
          "app-tab",
          `app-tab-${variant}`,
          route.label === "Danger Zone" && "app-tab-danger",
          isActive && "app-tab-active"
        )
      }
    >
      {route.label}
    </NavLink>
  );

  return (
    <div className="app-shell">
      <header className="app-header">
        <div>
          <h1>VitalServer Helper</h1>
          <p>Helper Console</p>
        </div>
      </header>

      <nav className="app-tabs" aria-label="Helper Console tabs">
        <div className="app-tab-primary-group">
          {primaryRoutes.map((route) => routeLink(route, "primary"))}
        </div>

        <div className="app-tab-utility-group">
          {utilityRoutes.map((route) => routeLink(route, "utility"))}
          {overflowRoutes.length > 0 ? (
            <details className="app-tab-menu">
              <summary
                className={cn(
                  "app-tab",
                  "app-tab-utility",
                  "app-tab-menu-button",
                  overflowActive && "app-tab-active"
                )}
              >
                More
              </summary>
              <div className="app-tab-menu-list">
                {overflowRoutes.map((route) => routeLink(route, "overflow"))}
              </div>
            </details>
          ) : null}
        </div>
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

function routeMatchesPath(route: RuntimeControlRoute, pathname: string) {
  return route.path === "/" ? pathname === "/" : pathname === route.path;
}
