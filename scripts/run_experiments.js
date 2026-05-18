#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const RESULTS = path.join(ROOT, "results");
const FIGURES = path.join(ROOT, "figures");
const REPORTS = path.join(ROOT, "reports");

const ACTIVE = "ACTIVE";
const PENDING_OUT = "PENDING_OUT";
const PENDING_IN = "PENDING_IN";
const FINALIZED = "FINALIZED_ACTIVE";

const operations = [
  { id: "transferFrom", label: "transferFrom" },
  { id: "safeTransferFrom", label: "safeTransferFrom" },
  { id: "approve", label: "approve" },
  { id: "setApprovalForAll", label: "setApprovalForAll" },
  { id: "directList", label: "list(tokenId)" },
  { id: "marketplaceList", label: "marketplace.list" },
];

const states = [
  { id: ACTIVE, label: "ACTIVE" },
  { id: PENDING_OUT, label: "PENDING_OUT" },
  { id: PENDING_IN, label: "PENDING_IN" },
  { id: FINALIZED, label: "FINALIZED" },
];

class BaselineNFTModel {
  constructor() {
    this.owner = new Map();
    this.approved = new Map();
    this.operatorApproval = new Map();
    this.listed = new Set();
    this.marketListed = new Set();
  }

  mint(to, tokenId) {
    if (this.owner.has(tokenId)) throw new Error("TokenAlreadyMinted");
    this.owner.set(tokenId, to);
  }

  ownerOf(tokenId) {
    const owner = this.owner.get(tokenId);
    if (!owner) throw new Error("TokenNotMinted");
    return owner;
  }

  bridgeOut(tokenId, caller) {
    this._requireAuthorized(caller, tokenId);
  }

  markPendingIn() {
    // Baseline has no explicit pending-in state.
  }

  finalizeIn(tokenId, newOwner) {
    this.owner.set(tokenId, newOwner);
    this.approved.delete(tokenId);
  }

  transferFrom(from, to, tokenId, caller) {
    this._requireAuthorized(caller, tokenId);
    if (this.ownerOf(tokenId) !== from) throw new Error("WrongOwner");
    this.owner.set(tokenId, to);
    this.approved.delete(tokenId);
  }

  safeTransferFrom(from, to, tokenId, caller) {
    this.transferFrom(from, to, tokenId, caller);
  }

  approve(to, tokenId, caller) {
    this._requireOwner(caller, tokenId);
    this.approved.set(tokenId, to);
  }

  setApprovalForAll(operator, approved, caller) {
    this.operatorApproval.set(`${caller}:${operator}`, approved);
  }

  list(tokenId, caller) {
    this._requireAuthorized(caller, tokenId);
    this.listed.add(tokenId);
  }

  marketplaceList(tokenId, caller) {
    this._requireAuthorized(caller, tokenId);
    this.marketListed.add(tokenId);
  }

  _requireOwner(caller, tokenId) {
    if (this.ownerOf(tokenId) !== caller) throw new Error("NotOwner");
  }

  _requireAuthorized(caller, tokenId) {
    const owner = this.ownerOf(tokenId);
    if (
      owner !== caller &&
      this.approved.get(tokenId) !== caller &&
      this.operatorApproval.get(`${owner}:${caller}`) !== true
    ) {
      throw new Error("NotOwnerOrApproved");
    }
  }
}

class SafeCrossChainNFTModel extends BaselineNFTModel {
  constructor() {
    super();
    this.state = new Map();
    this.pendingTokenCount = new Map();
    this.finalizedMessages = new Set();
  }

  mint(to, tokenId) {
    super.mint(to, tokenId);
    this.state.set(tokenId, ACTIVE);
  }

  bridgeOut(tokenId, caller) {
    this._requireActive(tokenId);
    super.bridgeOut(tokenId, caller);
    this.state.set(tokenId, PENDING_OUT);
    const owner = this.ownerOf(tokenId);
    this.pendingTokenCount.set(owner, (this.pendingTokenCount.get(owner) || 0) + 1);
  }

  markPendingIn(tokenId) {
    this._requireActive(tokenId);
    this.state.set(tokenId, PENDING_IN);
    const owner = this.ownerOf(tokenId);
    this.pendingTokenCount.set(owner, (this.pendingTokenCount.get(owner) || 0) + 1);
  }

  finalizeIn(tokenId, newOwner, messageId) {
    if (this.finalizedMessages.has(messageId)) throw new Error("MessageAlreadyFinalized");
    this.finalizedMessages.add(messageId);
    const oldOwner = this.owner.get(tokenId);
    if (oldOwner && this.state.get(tokenId) !== ACTIVE) {
      this.pendingTokenCount.set(oldOwner, (this.pendingTokenCount.get(oldOwner) || 1) - 1);
    }
    super.finalizeIn(tokenId, newOwner);
    this.state.set(tokenId, ACTIVE);
  }

  transferFrom(from, to, tokenId, caller) {
    this._requireActive(tokenId);
    super.transferFrom(from, to, tokenId, caller);
  }

  safeTransferFrom(from, to, tokenId, caller) {
    this._requireActive(tokenId);
    super.safeTransferFrom(from, to, tokenId, caller);
  }

  approve(to, tokenId, caller) {
    this._requireActive(tokenId);
    super.approve(to, tokenId, caller);
  }

  setApprovalForAll(operator, approved, caller) {
    if ((this.pendingTokenCount.get(caller) || 0) !== 0) {
      throw new Error("OperatorApprovalWhileOwnerHasPendingTokens");
    }
    super.setApprovalForAll(operator, approved, caller);
  }

  list(tokenId, caller) {
    this._requireActive(tokenId);
    super.list(tokenId, caller);
  }

  marketplaceList(tokenId, caller) {
    this._requireActive(tokenId);
    super.marketplaceList(tokenId, caller);
  }

  _requireActive(tokenId) {
    if (this.state.get(tokenId) !== ACTIVE) {
      throw new Error("HazardousOperationWhilePending");
    }
  }
}

function ensureDirs() {
  for (const dir of [RESULTS, FIGURES, REPORTS]) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function attempt(fn) {
  try {
    fn();
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

function setup(system, state, tokenId) {
  const nft = system === "baseline" ? new BaselineNFTModel() : new SafeCrossChainNFTModel();
  nft.mint("alice", tokenId);

  if (state === PENDING_OUT) {
    nft.bridgeOut(tokenId, "alice");
  } else if (state === PENDING_IN) {
    nft.markPendingIn(tokenId, "alice");
  } else if (state === FINALIZED) {
    nft.bridgeOut(tokenId, "alice");
    nft.finalizeIn(tokenId, "alice", `msg-${tokenId}`);
  }

  return nft;
}

function runOperation(nft, operationId, tokenId) {
  if (operationId === "transferFrom") {
    nft.transferFrom("alice", "bob", tokenId, "alice");
  } else if (operationId === "safeTransferFrom") {
    nft.safeTransferFrom("alice", "bob", tokenId, "alice");
  } else if (operationId === "approve") {
    nft.approve("mallory", tokenId, "alice");
  } else if (operationId === "setApprovalForAll") {
    nft.setApprovalForAll("operator", true, "alice");
  } else if (operationId === "directList") {
    nft.list(tokenId, "alice");
  } else if (operationId === "marketplaceList") {
    nft.marketplaceList(tokenId, "alice");
  } else {
    throw new Error(`Unknown operation: ${operationId}`);
  }
}

function buildOperationMatrix() {
  const rows = [];
  let tokenId = 1;
  for (const system of ["baseline", "proposal"]) {
    for (const state of states) {
      for (const operation of operations) {
        const nft = setup(system, state.id, tokenId);
        const result = attempt(() => runOperation(nft, operation.id, tokenId));
        const hazardousPending = state.id === PENDING_OUT || state.id === PENDING_IN;
        rows.push({
          system,
          state: state.id,
          operation: operation.id,
          ok: result.ok,
          error: result.error || null,
          expectedSafeOutcome: hazardousPending ? "reject" : "allow",
          safetyCorrect:
            system === "proposal"
              ? (hazardousPending ? !result.ok : result.ok)
              : true,
          riskExposure:
            system === "baseline" && hazardousPending && result.ok,
        });
        tokenId += 1;
      }
    }
  }
  return rows;
}

function runReplayExperiment() {
  const baseline = setup("baseline", FINALIZED, 1000);
  const proposal = setup("proposal", FINALIZED, 1001);
  return {
    baseline: attempt(() => baseline.finalizeIn(1000, "alice", "msg-1000")),
    proposal: attempt(() => proposal.finalizeIn(1001, "alice", "msg-1001")),
  };
}

function summarize(matrix, replay) {
  const pending = matrix.filter((r) => r.state === PENDING_OUT || r.state === PENDING_IN);
  const active = matrix.filter((r) => r.state === ACTIVE);
  const finalized = matrix.filter((r) => r.state === FINALIZED);
  const baselinePending = pending.filter((r) => r.system === "baseline");
  const proposalPending = pending.filter((r) => r.system === "proposal");
  const proposalActive = active.filter((r) => r.system === "proposal");
  const proposalFinalized = finalized.filter((r) => r.system === "proposal");

  return {
    generatedAt: new Date().toISOString(),
    operations: operations.map((o) => o.id),
    states: states.map((s) => s.id),
    pendingHazardousAttemptsPerSystem: proposalPending.length,
    baselinePendingAllowed: baselinePending.filter((r) => r.ok).length,
    baselinePendingAllowedTotal: baselinePending.length,
    proposalPendingRejected: proposalPending.filter((r) => !r.ok).length,
    proposalPendingRejectedTotal: proposalPending.length,
    proposalActiveAllowed: proposalActive.filter((r) => r.ok).length,
    proposalActiveAllowedTotal: proposalActive.length,
    proposalFinalizedAllowed: proposalFinalized.filter((r) => r.ok).length,
    proposalFinalizedAllowedTotal: proposalFinalized.length,
    baselineReplayAccepted: replay.baseline.ok,
    proposalReplayRejected: !replay.proposal.ok,
    headline:
      `baseline permits ${baselinePending.filter((r) => r.ok).length}/${baselinePending.length} ` +
      `pending hazardous operations; proposal rejects ${proposalPending.filter((r) => !r.ok).length}/${proposalPending.length} ` +
      `and restores ${proposalFinalized.filter((r) => r.ok).length}/${proposalFinalized.length} after finalization.`,
  };
}

function stateAccessOverheadModel() {
  return [
    {
      operation: "transferFrom",
      baselineReads: 1,
      proposalExtraReads: 1,
      proposalExtraWrites: 0,
      explanation: "bridgeState[tokenId] read before owner/approval checks",
    },
    {
      operation: "safeTransferFrom",
      baselineReads: 1,
      proposalExtraReads: 1,
      proposalExtraWrites: 0,
      explanation: "same guard as transferFrom",
    },
    {
      operation: "approve",
      baselineReads: 1,
      proposalExtraReads: 1,
      proposalExtraWrites: 0,
      explanation: "bridgeState[tokenId] read before approval",
    },
    {
      operation: "setApprovalForAll",
      baselineReads: 0,
      proposalExtraReads: 1,
      proposalExtraWrites: 0,
      explanation: "pendingTokenCount[msg.sender] read",
    },
    {
      operation: "list",
      baselineReads: 1,
      proposalExtraReads: 1,
      proposalExtraWrites: 0,
      explanation: "bridgeState[tokenId] read before listing",
    },
    {
      operation: "bridgeOut",
      baselineReads: 1,
      proposalExtraReads: 1,
      proposalExtraWrites: 2,
      explanation: "bridgeState write and pendingTokenCount write",
    },
    {
      operation: "finalizeIn",
      baselineReads: 0,
      proposalExtraReads: 1,
      proposalExtraWrites: 3,
      explanation: "message replay guard, state restore, pending count update",
    },
  ];
}

function writeJson(name, value) {
  fs.writeFileSync(path.join(RESULTS, name), `${JSON.stringify(value, null, 2)}\n`);
}

function escapeXml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function matrixCellColor(row) {
  if (row.state === ACTIVE || row.state === FINALIZED) {
    return row.ok ? "#e7ece6" : "#ead9cf";
  }
  if (row.system === "baseline") {
    return row.ok ? "#ead9cf" : "#e7ece6";
  }
  return row.ok ? "#ead9cf" : "#e7ece6";
}

function matrixCellStroke(row) {
  if (row.state === ACTIVE || row.state === FINALIZED) {
    return row.ok ? "#6f7f69" : "#8a6258";
  }
  if (row.system === "baseline") {
    return row.ok ? "#8a6258" : "#6f7f69";
  }
  return row.ok ? "#8a6258" : "#6f7f69";
}

function matrixCellLabel(row) {
  if (row.state === ACTIVE || row.state === FINALIZED) {
    return row.ok ? "ALLOW" : "BLOCK";
  }
  if (row.system === "baseline") {
    return row.ok ? "RISK" : "BLOCK";
  }
  return row.ok ? "RISK" : "BLOCK";
}

function writeOperationMatrixSvg(matrix) {
  const cellW = 116;
  const cellH = 34;
  const left = 210;
  const top = 66;
  const panelGap = 44;
  const panelH = operations.length * cellH + 38;
  const width = left + states.length * cellW + 40;
  const height = top + panelH * 2 + panelGap + 42;
  const panels = ["baseline", "proposal"];
  const lines = [];

  lines.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`);
  lines.push(`<rect width="100%" height="100%" fill="#fbfaf8"/>`);
  lines.push(`<text x="24" y="28" font-family="Arial, sans-serif" font-size="19" font-weight="700" fill="#20242a">Hazardous NFT Operation Matrix</text>`);
  lines.push(`<text x="24" y="50" font-family="Arial, sans-serif" font-size="12" fill="#5d6470">Pending cells distinguish executable hazards from blocked operations.</text>`);

  for (let p = 0; p < panels.length; p += 1) {
    const system = panels[p];
    const y0 = top + p * (panelH + panelGap);
    lines.push(`<text x="24" y="${y0 + 22}" font-family="Arial, sans-serif" font-size="15" font-weight="700" fill="#20242a">${system === "baseline" ? "Baseline" : "Proposal"}</text>`);

    for (let c = 0; c < states.length; c += 1) {
      const x = left + c * cellW;
      lines.push(`<text x="${x + cellW / 2}" y="${y0 + 22}" font-family="Arial, sans-serif" font-size="11" font-weight="700" text-anchor="middle" fill="#2c3138">${states[c].label}</text>`);
    }

    for (let r = 0; r < operations.length; r += 1) {
      const y = y0 + 38 + r * cellH;
      lines.push(`<text x="24" y="${y + 22}" font-family="Arial, sans-serif" font-size="11" fill="#2c3138">${escapeXml(operations[r].label)}</text>`);
      for (let c = 0; c < states.length; c += 1) {
        const state = states[c].id;
        const row = matrix.find((item) => item.system === system && item.state === state && item.operation === operations[r].id);
        const x = left + c * cellW;
        const color = matrixCellColor(row);
        const stroke = matrixCellStroke(row);
        const label = matrixCellLabel(row);
        lines.push(`<rect x="${x}" y="${y}" width="${cellW - 4}" height="${cellH - 4}" rx="2" fill="${color}" stroke="${stroke}" stroke-width="1"/>`);
        lines.push(`<text x="${x + (cellW - 4) / 2}" y="${y + 20}" font-family="Arial, sans-serif" font-size="11" font-weight="700" text-anchor="middle" fill="#20242a">${label}</text>`);
      }
    }
  }

  lines.push(`<rect x="24" y="${height - 28}" width="12" height="12" fill="#ead9cf" stroke="#8a6258"/><text x="42" y="${height - 18}" font-family="Arial, sans-serif" font-size="11" fill="#333">hazard remains executable</text>`);
  lines.push(`<rect x="216" y="${height - 28}" width="12" height="12" fill="#e7ece6" stroke="#6f7f69"/><text x="234" y="${height - 18}" font-family="Arial, sans-serif" font-size="11" fill="#333">safe outcome</text>`);
  lines.push(`</svg>`);
  fs.writeFileSync(path.join(FIGURES, "operation_matrix.svg"), `${lines.join("\n")}\n`);
}

function writeOverheadSvg(overhead) {
  const width = 820;
  const height = 370;
  const left = 80;
  const top = 54;
  const chartH = 220;
  const barW = 56;
  const gap = 42;
  const maxValue = Math.max(...overhead.map((o) => o.proposalExtraReads + o.proposalExtraWrites));
  const lines = [];
  lines.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`);
  lines.push(`<defs><pattern id="writeHatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="#6b625a" stroke-width="1"/></pattern></defs>`);
  lines.push(`<rect width="100%" height="100%" fill="#fbfaf8"/>`);
  lines.push(`<text x="24" y="28" font-family="Arial, sans-serif" font-size="19" font-weight="700" fill="#20242a">State-Access Overhead Model</text>`);
  lines.push(`<text x="24" y="48" font-family="Arial, sans-serif" font-size="12" fill="#5d6470">Hazardous operations add one state read; bridge transitions perform the writes.</text>`);
  lines.push(`<line x1="${left}" y1="${top + chartH}" x2="${width - 40}" y2="${top + chartH}" stroke="#2c3138"/>`);
  lines.push(`<line x1="${left}" y1="${top}" x2="${left}" y2="${top + chartH}" stroke="#2c3138"/>`);

  for (let i = 0; i <= maxValue; i += 1) {
    const y = top + chartH - (i / maxValue) * chartH;
    lines.push(`<line x1="${left - 4}" y1="${y}" x2="${width - 40}" y2="${y}" stroke="#dedbd4"/>`);
    lines.push(`<text x="${left - 12}" y="${y + 4}" font-family="Arial, sans-serif" font-size="10" text-anchor="end" fill="#5d6470">${i}</text>`);
  }

  overhead.forEach((item, i) => {
    const x = left + 28 + i * (barW + gap);
    const reads = item.proposalExtraReads;
    const writes = item.proposalExtraWrites;
    const readH = (reads / maxValue) * chartH;
    const writeH = (writes / maxValue) * chartH;
    const baseY = top + chartH;
    lines.push(`<rect x="${x}" y="${baseY - readH}" width="${barW}" height="${readH}" fill="#c9ced8" stroke="#677085"/>`);
    lines.push(`<rect x="${x}" y="${baseY - readH - writeH}" width="${barW}" height="${writeH}" fill="#e6dfd5" stroke="#6b625a"/>`);
    if (writes > 0) {
      lines.push(`<rect x="${x}" y="${baseY - readH - writeH}" width="${barW}" height="${writeH}" fill="url(#writeHatch)" opacity="0.45"/>`);
    }
    lines.push(`<text x="${x + barW / 2}" y="${baseY - readH - writeH - 6}" font-family="Arial, sans-serif" font-size="11" font-weight="700" text-anchor="middle" fill="#111">${reads + writes}</text>`);
    lines.push(`<text x="${x + barW / 2}" y="${baseY + 18}" font-family="Arial, sans-serif" font-size="10" text-anchor="middle" fill="#333">${escapeXml(item.operation)}</text>`);
  });

  lines.push(`<rect x="606" y="30" width="12" height="12" fill="#c9ced8" stroke="#677085"/><text x="624" y="40" font-family="Arial, sans-serif" font-size="11" fill="#333">extra reads</text>`);
  lines.push(`<rect x="706" y="30" width="12" height="12" fill="#e6dfd5" stroke="#6b625a"/><text x="724" y="40" font-family="Arial, sans-serif" font-size="11" fill="#333">extra writes</text>`);
  lines.push(`</svg>`);
  fs.writeFileSync(path.join(FIGURES, "state_access_overhead.svg"), `${lines.join("\n")}\n`);
}

function writeTimelineSvg() {
  const width = 900;
  const height = 300;
  const lines = [];
  lines.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`);
  lines.push(`<rect width="100%" height="100%" fill="#fbfaf8"/>`);
  lines.push(`<text x="24" y="30" font-family="Arial, sans-serif" font-size="19" font-weight="700" fill="#20242a">Pending Window Attack Surface</text>`);
  lines.push(`<text x="24" y="52" font-family="Arial, sans-serif" font-size="12" fill="#5d6470">The relay delay creates a window in which ownership-dependent operations must be gated.</text>`);
  const xs = [120, 320, 560, 760];
  const labels = ["bridgeOut", "pending window", "hazardous op", "finalizeIn"];
  for (let row = 0; row < 2; row += 1) {
    const y = row === 0 ? 118 : 218;
    const title = row === 0 ? "Baseline" : "Proposal";
    lines.push(`<text x="24" y="${y + 5}" font-family="Arial, sans-serif" font-size="15" font-weight="700" fill="#20242a">${title}</text>`);
    lines.push(`<line x1="${xs[0]}" y1="${y}" x2="${xs[3]}" y2="${y}" stroke="#3a4048" stroke-width="2"/>`);
    for (let i = 0; i < xs.length; i += 1) {
      lines.push(`<circle cx="${xs[i]}" cy="${y}" r="6" fill="#fbfaf8" stroke="#3a4048" stroke-width="2"/>`);
      lines.push(`<text x="${xs[i]}" y="${y + 30}" font-family="Arial, sans-serif" font-size="11" text-anchor="middle" fill="#2c3138">${labels[i]}</text>`);
    }
    const fill = row === 0 ? "#ead9cf" : "#e7ece6";
    const stroke = row === 0 ? "#8a6258" : "#6f7f69";
    const text = row === 0 ? "transfer / approve / listing succeeds" : "operation reverts until finalization";
    lines.push(`<rect x="${xs[1] + 38}" y="${y - 24}" width="250" height="28" rx="2" fill="${fill}" stroke="${stroke}"/>`);
    lines.push(`<text x="${xs[1] + 163}" y="${y - 6}" font-family="Arial, sans-serif" font-size="12" font-weight="700" text-anchor="middle" fill="#20242a">${text}</text>`);
  }
  lines.push(`</svg>`);
  fs.writeFileSync(path.join(FIGURES, "pending_window_timeline.svg"), `${lines.join("\n")}\n`);
}

function writeReport(summary, matrix, replay, overhead) {
  const lines = [];
  lines.push("# FIT2026 Experiment Report");
  lines.push("");
  lines.push(`Generated at: ${summary.generatedAt}`);
  lines.push("");
  lines.push("## Headline Result");
  lines.push("");
  lines.push(summary.headline);
  lines.push("");
  lines.push("Evidence levels: the matrix and figures are generated from an executable model matching the intended Solidity behavior; `test/ScenarioMatrix.t.sol` provides EVM-level checks when run with Foundry; the overhead figure is a storage-access model, not a measured gas benchmark.");
  lines.push("");
  lines.push("| Metric | Result |");
  lines.push("| --- | ---: |");
  lines.push(`| Baseline pending hazardous operations allowed | ${summary.baselinePendingAllowed}/${summary.baselinePendingAllowedTotal} |`);
  lines.push(`| Proposal pending hazardous operations rejected | ${summary.proposalPendingRejected}/${summary.proposalPendingRejectedTotal} |`);
  lines.push(`| Proposal ACTIVE operations allowed | ${summary.proposalActiveAllowed}/${summary.proposalActiveAllowedTotal} |`);
  lines.push(`| Proposal post-finalization operations allowed | ${summary.proposalFinalizedAllowed}/${summary.proposalFinalizedAllowedTotal} |`);
  lines.push(`| Baseline replay finalization accepted | ${summary.baselineReplayAccepted ? "yes" : "no"} |`);
  lines.push(`| Proposal replay finalization rejected | ${summary.proposalReplayRejected ? "yes" : "no"} |`);
  lines.push("");
  lines.push("## Figures");
  lines.push("");
  lines.push("- `figures/operation_matrix.svg`: baseline/proposal operation matrix.");
  lines.push("- `figures/pending_window_timeline.svg`: pending-window attack timeline.");
  lines.push("- `figures/state_access_overhead.svg`: state-access overhead model.");
  lines.push("");
  lines.push("## Operation Matrix");
  lines.push("");
  lines.push("| System | State | Operation | Outcome | Error |");
  lines.push("| --- | --- | --- | --- | --- |");
  for (const row of matrix) {
    lines.push(`| ${row.system} | ${row.state} | ${row.operation} | ${row.ok ? "allow" : "reject"} | ${row.error || ""} |`);
  }
  lines.push("");
  lines.push("## Replay Finalization");
  lines.push("");
  lines.push(`- Baseline: ${replay.baseline.ok ? "accepted" : `rejected (${replay.baseline.error})`}`);
  lines.push(`- Proposal: ${replay.proposal.ok ? "accepted" : `rejected (${replay.proposal.error})`}`);
  lines.push("");
  lines.push("## State-Access Overhead Model");
  lines.push("");
  lines.push("This is a storage-access model, not a chain-specific gas benchmark. The executable Solidity tests are in `test/ScenarioMatrix.t.sol` and can be run with `forge test --gas-report` or `docker compose run --rm foundry`.");
  lines.push("");
  lines.push("| Operation | Extra reads | Extra writes | Explanation |");
  lines.push("| --- | ---: | ---: | --- |");
  for (const item of overhead) {
    lines.push(`| ${item.operation} | ${item.proposalExtraReads} | ${item.proposalExtraWrites} | ${item.explanation} |`);
  }
  lines.push("");
  fs.writeFileSync(path.join(REPORTS, "experiment_report.md"), `${lines.join("\n")}\n`);
}

function main() {
  ensureDirs();
  const matrix = buildOperationMatrix();
  const replay = runReplayExperiment();
  const summary = summarize(matrix, replay);
  const overhead = stateAccessOverheadModel();

  writeJson("operation_matrix.json", matrix);
  writeJson("replay_report.json", replay);
  writeJson("experiment_summary.json", summary);
  writeJson("state_access_overhead.json", overhead);
  writeOperationMatrixSvg(matrix);
  writeTimelineSvg();
  writeOverheadSvg(overhead);
  writeReport(summary, matrix, replay, overhead);

  console.log(summary.headline);
  console.log(`proposal active availability: ${summary.proposalActiveAllowed}/${summary.proposalActiveAllowedTotal}`);
  console.log(`proposal post-finalization availability: ${summary.proposalFinalizedAllowed}/${summary.proposalFinalizedAllowedTotal}`);
  console.log(`proposal replay rejection: ${summary.proposalReplayRejected ? "PASS" : "FAIL"}`);

  const pass =
    summary.baselinePendingAllowed === summary.baselinePendingAllowedTotal &&
    summary.proposalPendingRejected === summary.proposalPendingRejectedTotal &&
    summary.proposalActiveAllowed === summary.proposalActiveAllowedTotal &&
    summary.proposalFinalizedAllowed === summary.proposalFinalizedAllowedTotal &&
    summary.proposalReplayRejected;

  console.log(`overall=${pass ? "PASS" : "FAIL"}`);
  if (!pass) {
    process.exitCode = 1;
  }
}

main();
