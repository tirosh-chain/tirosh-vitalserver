export type VrIdentityRewritePolicy = {
  enabled?: boolean;
  verifyDelaysMs?: number[];
};

export type VrIdentityStorePort = {
  setRecorderIp(vrcode: string, selectedIp: string | null | undefined, policy: VrIdentityRewritePolicy): void;
};
