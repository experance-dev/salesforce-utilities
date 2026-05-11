/**
 * @description Base exception class for the Utilities module. Downstream modules extend this to create
 *              typed exceptions that share a common catch point for utilities-layer errors.
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @group Utilities
 */
public inherited sharing virtual class UtilitiesModuleException extends Exception {}
