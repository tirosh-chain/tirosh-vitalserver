import { useEffect, useRef, useState } from "react";
import { Navigate, NavLink, Route, Routes, useLocation } from "react-router-dom";

import { cn } from "@/components/cn";
import { consoleRoutes, type ConsoleRoute } from "./routes";

export function App() {
  const location = useLocation();
  const overflowMenuRef = useRef<HTMLDetailsElement>(null);
  const [overflowMenuOpen, setOverflowMenuOpen] = useState(false);
  const visibleRoutes = consoleRoutes;
  const primaryRoutes = visibleRoutes.filter((route) => route.group === "primary");
  const utilityRoutes = visibleRoutes.filter((route) => route.group === "utility");
  const overflowRoutes = visibleRoutes.filter((route) => route.group === "overflow");
  const overflowActive = overflowRoutes.some((route) =>
    routeMatchesPath(route, location.pathname)
  );

  useEffect(() => {
    setOverflowMenuOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!overflowMenuOpen) {
      return;
    }

    const closeOnOutsidePointerDown = (event: PointerEvent) => {
      if (!overflowMenuRef.current?.contains(event.target as Node)) {
        setOverflowMenuOpen(false);
      }
    };

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOverflowMenuOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeOnOutsidePointerDown);
    document.addEventListener("keydown", closeOnEscape);

    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePointerDown);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [overflowMenuOpen]);

  const routeLink = (
    route: ConsoleRoute,
    variant: "primary" | "utility" | "overflow"
  ) => (
    <NavLink
      key={route.path}
      to={route.path}
      end={route.path === "/"}
      onClick={() => {
        if (variant === "overflow") {
          setOverflowMenuOpen(false);
        }
      }}
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
          <p>Remote Console</p>
        </div>
      </header>

      <nav className="app-tabs" aria-label="Remote Console tabs">
        <div className="app-tab-primary-group">
          {primaryRoutes.map((route) => routeLink(route, "primary"))}
        </div>

        <div className="app-tab-utility-group">
          {utilityRoutes.map((route) => routeLink(route, "utility"))}
          {overflowRoutes.length > 0 ? (
            <details
              ref={overflowMenuRef}
              className="app-tab-menu"
              open={overflowMenuOpen}
              onToggle={(event) =>
                setOverflowMenuOpen(event.currentTarget.open)
              }
            >
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

function routeMatchesPath(route: ConsoleRoute, pathname: string) {
  return route.path === "/" ? pathname === "/" : pathname === route.path;
}
