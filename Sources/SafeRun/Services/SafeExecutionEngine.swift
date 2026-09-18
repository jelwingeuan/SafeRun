import Foundation

struct SafeExecutionEngine: Sendable {
    func validateApproval(plan: SafeRunPlan, simulation: SimulationResult, userApproved: Bool) throws {
        guard userApproved else {
            throw SafeRunError.executionUnavailable
        }
        guard plan.status == .simulationComplete || plan.status == .approved else {
            throw SafeRunError.planNotExecutable("SafeRun requires a completed simulation before execution.")
        }
        guard simulation.canExecute else {
            throw SafeRunError.planNotExecutable("Resolve the listed conflicts before running this plan.")
        }
    }
}
