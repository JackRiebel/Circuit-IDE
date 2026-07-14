/// Typed, user-visible evidence requirements for enterprise artifacts.
///
/// A contract field is deliberately separate from a renderer's generic file
/// readiness checks.  It answers whether the decision evidence necessary for
/// a particular artifact is present, not just whether the file was produced.
enum ArtifactContractField {
  assumptions('Assumptions'),
  checkedDate('Checked date'),
  confidence('Confidence'),
  sources('Sources'),
  topologyGraph('Topology graph'),
  topologyCapacity('Topology capacity validation'),
  reviewFindings('Review findings'),
  reviewRisks('Risk register'),
  reviewValidation('Validation plan'),
  poeBudget('PoE budget validation'),
  wanThroughput('WAN throughput validation'),
  candidateValidation('Candidate validation'),
  lifecycleDateAuthority('Lifecycle date authority'),
  replacementSuitability('Replacement suitability'),
  comparisonCandidates('Comparison candidates'),
  fitScoring('Fit scoring'),
  hardGateValidation('Hard-gate validation'),
  businessUseCases('Priority use cases'),
  businessValueMetrics('Value metrics'),
  chartData('Numeric chart data'),
  chartDecisionThresholds('Decision thresholds'),
  evidenceClaims('Claim register'),
  claimDisposition('Claim disposition');

  const ArtifactContractField(this.label);

  final String label;
}
