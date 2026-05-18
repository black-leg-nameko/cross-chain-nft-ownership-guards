#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ACTIVE = "ACTIVE";
const PENDING_OUT = "PENDING_OUT";

class BaselineNFTModel {
  constructor() {
    this.owner = new Map();
    this.approved = new Map();
    this.listed = new Set();
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
    this._requireOwner(caller, tokenId);
  }

  finalizeIn(tokenId, newOwner) {
    this.owner.set(tokenId, newOwner);
    this.approved.delete(tokenId);
  }

  transferFrom(from, to, tokenId, caller) {
    this._requireOwner(caller, tokenId);
    if (this.ownerOf(tokenId) !== from) throw new Error("WrongOwner");
    this.owner.set(tokenId, to);
    this.approved.delete(tokenId);
  }

  approve(to, tokenId, caller) {
    this._requireOwner(caller, tokenId);
    this.approved.set(tokenId, to);
  }

  list(tokenId, caller) {
    this._requireOwner(caller, tokenId);
    this.listed.add(tokenId);
  }

  _requireOwner(caller, tokenId) {
    if (this.ownerOf(tokenId) !== caller) throw new Error("NotOwner");
  }
}

class SafeCrossChainNFTModel extends BaselineNFTModel {
  constructor() {
    super();
    this.state = new Map();
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
  }

  finalizeIn(tokenId, newOwner, messageId) {
    if (this.finalizedMessages.has(messageId)) throw new Error("MessageAlreadyFinalized");
    this.finalizedMessages.add(messageId);
    super.finalizeIn(tokenId, newOwner);
    this.state.set(tokenId, ACTIVE);
  }

  transferFrom(from, to, tokenId, caller) {
    this._requireActive(tokenId);
    super.transferFrom(from, to, tokenId, caller);
  }

  approve(to, tokenId, caller) {
    this._requireActive(tokenId);
    super.approve(to, tokenId, caller);
  }

  list(tokenId, caller) {
    this._requireActive(tokenId);
    super.list(tokenId, caller);
  }

  _requireActive(tokenId) {
    if (this.state.get(tokenId) !== ACTIVE) {
      throw new Error("HazardousOperationWhilePending");
    }
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

function freshPair() {
  const baseline = new BaselineNFTModel();
  const proposal = new SafeCrossChainNFTModel();
  baseline.mint("alice", 1);
  proposal.mint("alice", 1);
  baseline.bridgeOut(1, "alice");
  proposal.bridgeOut(1, "alice");
  return { baseline, proposal };
}

const scenarios = [];

{
  const { baseline, proposal } = freshPair();
  scenarios.push({
    name: "pending transfer",
    baseline: attempt(() => baseline.transferFrom("alice", "bob", 1, "alice")),
    proposal: attempt(() => proposal.transferFrom("alice", "bob", 1, "alice")),
  });
}

{
  const { baseline, proposal } = freshPair();
  scenarios.push({
    name: "pending approve",
    baseline: attempt(() => baseline.approve("mallory", 1, "alice")),
    proposal: attempt(() => proposal.approve("mallory", 1, "alice")),
  });
}

{
  const { baseline, proposal } = freshPair();
  scenarios.push({
    name: "pending listing",
    baseline: attempt(() => baseline.list(1, "alice")),
    proposal: attempt(() => proposal.list(1, "alice")),
  });
}

{
  const { baseline, proposal } = freshPair();
  baseline.finalizeIn(1, "alice");
  proposal.finalizeIn(1, "alice", "msg-1");
  scenarios.push({
    name: "transfer after finalize",
    baseline: attempt(() => baseline.transferFrom("alice", "bob", 1, "alice")),
    proposal: attempt(() => proposal.transferFrom("alice", "bob", 1, "alice")),
  });
}

{
  const { baseline, proposal } = freshPair();
  baseline.finalizeIn(1, "alice");
  proposal.finalizeIn(1, "alice", "msg-1");
  scenarios.push({
    name: "replay finalize",
    baseline: attempt(() => baseline.finalizeIn(1, "alice")),
    proposal: attempt(() => proposal.finalizeIn(1, "alice", "msg-1")),
  });
}

const report = {
  generatedAt: new Date().toISOString(),
  scenarios,
  pass:
    scenarios[0].baseline.ok && !scenarios[0].proposal.ok &&
    scenarios[1].baseline.ok && !scenarios[1].proposal.ok &&
    scenarios[2].baseline.ok && !scenarios[2].proposal.ok &&
    scenarios[3].baseline.ok && scenarios[3].proposal.ok &&
    scenarios[4].baseline.ok && !scenarios[4].proposal.ok,
};

const outputPath = path.join(__dirname, "..", "results", "scenario_report.json");
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`);

for (const scenario of scenarios) {
  const baseline = scenario.baseline.ok ? "ok" : `revert:${scenario.baseline.error}`;
  const proposal = scenario.proposal.ok ? "ok" : `revert:${scenario.proposal.error}`;
  console.log(`${scenario.name}: baseline=${baseline}, proposal=${proposal}`);
}
console.log(`overall=${report.pass ? "PASS" : "FAIL"}`);

if (!report.pass) {
  process.exitCode = 1;
}
