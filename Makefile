.PHONY: lint docs template clean

lint:
	docker run --rm -v "$$(pwd):/work" -w /work quay.io/helmpack/chart-testing:latest ct lint --config ct.yaml

docs:
	docker run --rm -v "$$(pwd):/helm-docs" -w /helm-docs jnorwood/helm-docs:latest

template:
	@if [ -z "$(CHART)" ]; then echo "Usage: make template CHART=geth"; exit 1; fi
	helm dependency update charts/$(CHART)
	helm template test charts/$(CHART)

clean:
	find charts -name "Chart.lock" -delete
	find charts -name "charts" -type d -exec rm -rf {} + 2>/dev/null || true
