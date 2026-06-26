import Foundation
import HealthKit

enum HealthKitManager {
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func syncTodaySteps(completion: @escaping (Result<Int, String>) -> Void) {
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
            fetchTodaySteps(stepType: stepType, completion: completion)
        }
    }

    private static func fetchTodaySteps(
        stepType: HKQuantityType,
        completion: @escaping (Result<Int, String>) -> Void
    ) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: Date(),
            options: .strictStartDate
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
