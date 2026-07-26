# Upstream placement profiles

These files declare which provider identity a deployment selects. They contain only public references and capability expectations; endpoint addresses and credentials are owned by a deployment secret/configuration adapter, never copied into a RuntimeTopology or profile file.

`external-upstream.v1.json` and `outbound-relay.v1.json` are intentionally independent. A relay can be selected without an external upstream, and neither declaration is a lifecycle/update/backup policy for the bundled stack.
