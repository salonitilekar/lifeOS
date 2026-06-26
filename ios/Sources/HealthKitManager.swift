import Foundation
import HealthKit

enum HealthKitManager {
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func syncSteps(completion: @escaping (Result<[String: Int], String>) -> Void) {
        guard isAvailable else {
            completion(.failure("unavailable"))
            return
        }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(.failure("type"))
            return
        }

        store.requestAuthorization(toShare: [], read: [stepType]) { granted, _ in
            guard granted else {
                completion(.failure("denied"))
                return
            }

            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
                completion(.failure("date"))
                return
            }

            var results: [String: Int] = [:]
            let group = DispatchGroup()
            var firstError: String?

            group.enter()
            fetchSteps(stepType: stepType, start: todayStart, end: Date()) { result in
                if case .success(let count) = result {
                    results[dateKey(for: Date())] = count
                }
                if case .failure(let code) = result {
                    firstError = firstError ?? code
                }
                group.leave()
            }

            group.enter()
            fetchSteps(stepType: stepType, start: yesterdayStart, end: todayStart) { result in
                if case .success(let count) = result {
                    results[dateKey(for: yesterdayStart)] = count
                }
                if case .failure(let code) = result {
                    firstError = firstError ?? code
                }
                group.leave()
            }

            group.notify(queue: .main) {
                if results.isEmpty, let error = firstError {
                    completion(.failure(error))
                    return
                }
                completion(.success(results))
            }
        }
    }

    private static func dateKey(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)-\(month)-\(day)"
    }

    private static func fetchSteps(
        stepType: HKQuantityType,
        start: Date,
        end: Date,
        completion: @escaping (Result<Int, String>) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if error != nil {
                completion(.failure("query"))
                return
            }
            let count = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            completion(.success(max(0, Int(count.rounded()))))
        }
        store.execute(query)
    }
}
